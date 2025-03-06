defmodule TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.{NonceExtractor, VenueExtractor}

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("🔄 Starting GeeksWhoDrink Index Job...")

    # Get the source record for this scraper
    source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

    # First, get the nonce needed for API calls
    case NonceExtractor.fetch_nonce() do
      {:ok, nonce} ->
        # Then fetch the venues using the nonce
        case fetch_venues(nonce) do
          {:ok, venues} ->
            # TESTING: Limit to 10 venues for testing purposes
            test_mode = System.get_env("TEST_MODE") == "true"
            venues = if test_mode do
              Logger.info("🧪 TEST MODE: Limiting to 10 venues for testing")
              Enum.take(venues, 10)
            else
              venues
            end

            Logger.info("✅ Successfully fetched #{length(venues)} venues from GeeksWhoDrink")

            # Enqueue detail jobs for each venue
            Logger.info("🔄 Enqueueing detail jobs for #{length(venues)} venues...")

            Enum.each(venues, fn venue_data ->
              # Log which venue we're processing for debugging
              Logger.info("🔄 Processing venue: #{venue_data.title}")

              # Enqueue a detail job for this venue
              %{venue: venue_data, source_id: source.id}
              |> TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkDetailJob.new()
              |> Oban.insert()
            end)

            {:ok, %{venue_count: length(venues)}}

          {:error, reason} ->
            Logger.error("❌ Failed to fetch venues: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to fetch nonce: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Reuse the venue fetching logic from the existing scraper
  defp fetch_venues(nonce) do
    base_url = "https://www.geekswhodrink.com/wp-admin/admin-ajax.php"
    base_params = %{
      "action" => "mb_display_mapped_events",
      "bounds[northLat]" => "71.35817123219137",
      "bounds[southLat]" => "-2.63233642366575",
      "bounds[westLong]" => "-174.787181",
      "bounds[eastLong]" => "-32.75593100000001",
      "days" => "",
      "brands" => "",
      "search" => "",
      "startLat" => "44.967243",
      "startLong" => "-103.771556",
      "searchInit" => "true",
      "tlCoord" => "",
      "brCoord" => "",
      "tlMapCoord" => "[-174.787181, 71.35817123219137]",
      "brMapCoord" => "[-32.75593100000001, -2.63233642366575]",
      "hasAll" => "true"
    }

    query_params = Map.put(base_params, "nonce", nonce)
    url = base_url <> "?" <> URI.encode_query(query_params)

    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        venues = parse_response(body)
        {:ok, venues}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP request failed with status #{status}"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp parse_response(body) do
    String.split(body, "<a id=\"quizBlock-")
    |> Enum.drop(1) # Drop the first empty element
    |> Enum.map(fn block ->
      "<a id=\"quizBlock-" <> block
    end)
    |> Enum.map(&extract_venue_info/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_venue_info(block) do
    case VenueExtractor.extract_venue_data(block) do
      {:ok, venue_data} -> venue_data
      _ -> nil
    end
  end
end

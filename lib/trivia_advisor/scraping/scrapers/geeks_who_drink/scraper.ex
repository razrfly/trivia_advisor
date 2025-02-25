defmodule TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.Scraper do
  require Logger
  alias TriviaAdvisor.Scraping.Helpers.VenueHelpers
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.{NonceExtractor, VenueExtractor, VenueDetailsExtractor}
  alias HtmlEntities

  @base_url "https://www.geekswhodrink.com/wp-admin/admin-ajax.php"
  @base_params %{
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

  def run do
    Logger.info("🔍 Fetching GeeksWhoDrink venues...")

    with {:ok, nonce} <- NonceExtractor.fetch_nonce(),
         {:ok, venues} <- fetch_venues(nonce) do
      Logger.info("✅ Found #{length(venues)} venues")
      {:ok, venues}
    else
      {:error, reason} ->
        Logger.error("❌ Failed to fetch venues: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_venues(nonce) do
    query_params = Map.put(@base_params, "nonce", nonce)
    url = @base_url <> "?" <> URI.encode_query(query_params)

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
    Logger.debug("Processing HTML block: #{inspect(block)}")
    case VenueExtractor.extract_venue_data(block) do
      {:ok, venue_data} ->
        raw_title = venue_data.title
        venue_data = Map.update!(venue_data, :title, &HtmlEntities.decode/1)

        # Parse time text for day of week
        day_of_week =
          with time_text when is_binary(time_text) and byte_size(time_text) > 3 <- venue_data.time_text,
               {:ok, parsed} <- TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time_text(time_text) do
            parsed.day_of_week
          else
            _ -> nil
          end

        # Fetch additional details from venue page
        additional_details =
          case VenueDetailsExtractor.extract_additional_details(venue_data.source_url) do
            {:ok, details} -> details
            _ -> %{}
          end

        venue_data
        |> Map.put(:raw_title, raw_title)
        |> Map.put(:day_of_week, day_of_week || "")
        |> Map.put(:start_time, nil)
        |> Map.put(:frequency, :weekly)
        |> Map.put(:description, nil)
        |> Map.put(:phone, nil)
        |> Map.put(:website, nil)
        |> Map.put(:fee_text, nil)
        |> Map.put(:facebook, nil)
        |> Map.put(:instagram, nil)
        |> Map.put(:hero_image_url, venue_data.logo_url)
        |> Map.merge(additional_details)
        |> tap(&VenueHelpers.log_venue_details/1)

      _ ->
        Logger.warning("Failed to extract venue info from block")
        nil
    end
  end
end

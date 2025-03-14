defmodule TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger
  import Ecto.Query

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.{NonceExtractor, VenueExtractor}
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Events.EventSource

  # Days threshold for skipping recently updated venues
  @skip_if_updated_within_days RateLimiter.skip_if_updated_within_days()

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting GeeksWhoDrink Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit") || Map.get(args, :limit)

    if limit do
      Logger.info("🧪 Testing mode: Limited to #{limit} venues")
    end

    # Get the source record for this scraper
    source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

    # First, get the nonce needed for API calls
    case NonceExtractor.fetch_nonce() do
      {:ok, nonce} ->
        # Then fetch the venues using the nonce
        case fetch_venues(nonce) do
          {:ok, raw_venues} ->
            # Apply limit if specified (for testing)
            venues_to_process = if limit do
              Logger.info("🧪 Taking first #{limit} venues from total of #{length(raw_venues)}")
              Enum.take(raw_venues, limit)
            else
              raw_venues
            end

            total_venues = length(venues_to_process)
            Logger.info("📊 Found #{total_venues} venues to process from GeeksWhoDrink")

            # Filter venues that were recently updated
            {to_process, to_skip} = filter_recently_updated_venues(venues_to_process, source.id)

            processed_count = length(to_process)
            skipped_count = length(to_skip)

            # Log skipped and processing counts
            Logger.info("⏩ Skipping #{skipped_count} venues updated within the last #{@skip_if_updated_within_days} days")
            Logger.info("🔄 Processing #{processed_count} venues that need updating")

            # Enqueue detail jobs with rate limiting
            enqueued_count = RateLimiter.schedule_detail_jobs(
              to_process,
              TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkDetailJob,
              fn venue_data ->
                %{venue: venue_data, source_id: source.id}
              end
            )

            Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing")

            # Create metadata for reporting
            metadata = %{
              "total_venues" => total_venues,
              "enqueued_jobs" => enqueued_count,
              "skipped_venues" => skipped_count,
              "applied_limit" => limit,
              "source_id" => source.id,
              "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }

            # Update job metadata
            Repo.update_all(
              from(j in "oban_jobs", where: j.id == ^job_id),
              set: [meta: metadata]
            )

            {:ok, %{venue_count: total_venues, enqueued_jobs: enqueued_count, skipped_venues: skipped_count}}

          {:error, reason} ->
            # Handle error and update job metadata
            error_metadata = %{
              "error" => inspect(reason),
              "error_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }

            Repo.update_all(
              from(j in "oban_jobs", where: j.id == ^job_id),
              set: [meta: error_metadata]
            )

            Logger.error("❌ Failed to fetch venues: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to fetch nonce: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Filter venues that were recently updated
  defp filter_recently_updated_venues(venues, source_id) do
    # Group venues with their source URLs for lookup
    venues_with_urls = Enum.map(venues, fn venue ->
      {venue, venue["source_url"]}
    end)

    # Get all URLs for lookup
    urls = Enum.map(venues_with_urls, fn {_, url} -> url end)

    # Find existing event sources for these venues
    existing_sources = from(es in EventSource,
      where: es.source_url in ^urls and es.source_id == ^source_id,
      select: {es.source_url, es.last_seen_at})
      |> Repo.all()
      |> Map.new()

    # Calculate threshold date (5 days ago)
    threshold_date = DateTime.utc_now() |> DateTime.add(-@skip_if_updated_within_days * 24 * 3600, :second)

    # Split venues into process and skip lists
    Enum.split_with(venues_with_urls, fn {venue, url} ->
      # Get last_seen_at for this URL
      last_seen_at = Map.get(existing_sources, url)

      case last_seen_at do
        nil ->
          # Venue not seen before, should process
          Logger.info("🆕 New venue not seen before: #{venue["title"]}")
          true

        last_seen_date ->
          # Check if venue was seen before the threshold
          case DateTime.compare(last_seen_date, threshold_date) do
            :lt ->
              # Last seen before cutoff date, should process
              Logger.info("🔄 Venue seen before cutoff date, will process: #{venue["title"]}")
              true
            _ ->
              # Last seen after cutoff date, should skip
              Logger.info("⏩ Skipping venue - recently seen: #{venue["title"]} on #{DateTime.to_iso8601(last_seen_date)}")
              false
          end
      end
    end)
    |> then(fn {to_process, to_skip} ->
      # Extract just the venue data from the tuples
      {
        Enum.map(to_process, fn {venue, _} -> venue end),
        Enum.map(to_skip, fn {venue, _} -> venue end)
      }
    end)
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

defmodule TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger
  import Ecto.Query

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.{NonceExtractor, VenueExtractor}
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Events.EventSource
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata

  # Days threshold for skipping recently updated venues
  @skip_if_updated_within_days RateLimiter.skip_if_updated_within_days()

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting GeeksWhoDrink Index Job...")

    # Store args in process dictionary for access in other functions
    Process.put(:job_args, args)

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit") || Map.get(args, :limit)

    # Check if we should force update all venues
    force_update = RateLimiter.force_update?(args)
    if force_update do
      Logger.info("⚠️ Force update enabled - will process ALL venues regardless of last update time")
    end

    # Extract the force_refresh_images flag using both string and atom keys for robustness
    force_refresh_images = Map.get(args, "force_refresh_images", false) ||
                           Map.get(args, :force_refresh_images, false)

    # Set process dictionary explicitly based on value
    if force_refresh_images do
      Logger.info("⚠️ Force image refresh enabled - will refresh ALL images")
      Process.put(:force_refresh_images, true)
    else
      # Explicitly set to false to ensure it's not using a stale value
      Process.put(:force_refresh_images, false)
    end

    # Log the extracted value for debugging
    Logger.info("🔍 Force refresh images flag: #{inspect(force_refresh_images)}")

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

            # Count venues to process and skip
            # Check if force update is enabled
            force_update = RateLimiter.force_update?(args)

            # Use the improved filtering logic
            {to_process, skipped_venues} = if force_update do
              # If force_update is true, process all venues
              Logger.info("🔄 Force update enabled - processing ALL venues")
              {venues_to_process, []}
            else
              # Otherwise filter based on last update time
              Enum.split_with(venues_to_process, fn venue ->
                # Ensure venue is a map with string keys
                venue_map = if is_map(venue) do
                  # Convert all keys to strings if they're not already
                  Enum.reduce(venue, %{}, fn {k, v}, acc ->
                    key = if is_atom(k), do: Atom.to_string(k), else: k
                    Map.put(acc, key, v)
                  end)
                else
                  venue
                end

                should_process_venue?(venue_map, source.id)
              end)
            end

            processed_count = length(to_process)
            skipped_count = length(skipped_venues)

            # Log skipped and processing counts
            Logger.info("⏩ Skipping #{skipped_count} venues updated within the last #{@skip_if_updated_within_days} days")
            Logger.info("🔄 Processing #{processed_count} venues that need updating")

            # Log the value being passed to detail jobs
            Logger.info("🔍 Will pass force_refresh_images=#{inspect(force_refresh_images)} to detail jobs")

            # Enqueue detail jobs with hourly rate limiting instead of basic rate limiting
            enqueued_count = RateLimiter.schedule_hourly_capped_jobs(
              to_process,
              TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkDetailJob,
              fn venue_data ->
                # Ensure venue data has string keys
                venue_map = if is_map(venue_data) do
                  # Convert all keys to strings if they're not already
                  Enum.reduce(venue_data, %{}, fn {k, v}, acc ->
                    key = if is_atom(k), do: Atom.to_string(k), else: k
                    Map.put(acc, key, v)
                  end)
                else
                  venue_data
                end

                # IMPORTANT: Use string keys for Oban job args
                detail_args = %{
                  "venue" => venue_map,
                  "source_id" => source.id,
                  "force_update" => force_update,  # Pass force_update flag to detail jobs
                  "force_refresh_images" => force_refresh_images  # Pass force_refresh_images flag
                }

                # Optional: Log the first job's args for debugging
                if venue_data == List.first(to_process) do
                  Logger.debug("🔍 First detail job args: #{inspect(detail_args)}")
                end

                detail_args
              end
            )

            Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing")

            # Create metadata for reporting
            metadata = %{
              total_venues: total_venues,
              enqueued_count: enqueued_count,
              skipped_count: skipped_count,
              applied_limit: limit,
              source_id: source.id,
              force_refresh_images: force_refresh_images,
              completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
            }

            # Update job metadata using JobMetadata helper
            JobMetadata.update_index_job(job_id, metadata)

            {:ok, %{venue_count: total_venues, enqueued_jobs: enqueued_count, skipped_venues: skipped_count}}

          {:error, reason} ->
            # Update job metadata with error using JobMetadata helper
            JobMetadata.update_error(job_id, reason, context: %{source_id: source.id})

            Logger.error("❌ Failed to fetch venues: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        # Update job metadata with error using JobMetadata helper
        JobMetadata.update_error(job_id, reason, context: %{source_id: source.id})

        Logger.error("❌ Failed to fetch nonce: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check if a venue should be processed based on its URL and last update time
  defp should_process_venue?(venue, source_id) do
    # Access venue data with string keys
    url = venue["source_url"]
    title = venue["title"] || "Unknown venue"

    # Handle nil or empty URLs
    if is_nil(url) or url == "" do
      Logger.info("🆕 New venue with no source URL, will process: #{title}")
      true
    else
      # Find existing event sources with this source_url
      case find_venues_by_source_url(url, source_id) do
        [] ->
          # No existing venues with this URL, should process
          Logger.info("🆕 New venue not seen before: #{title} (#{url})")
          true
        event_sources ->
          # Check if any of these event sources were updated within the threshold
          recently_processed = Enum.any?(event_sources, fn event_source ->
            recently_updated?(event_source)
          end)

          if recently_processed do
            # Venue was recently processed, should skip
            source = List.first(event_sources)
            Logger.info("⏩ Skipping venue - processed within last #{@skip_if_updated_within_days} days: #{title} (last seen: #{DateTime.to_iso8601(source.last_seen_at)})")
            false
          else
            # Venue hasn't been recently processed, should process
            source = List.first(event_sources)
            Logger.info("🔄 Venue seen before cutoff date, will process: #{title} (last seen: #{DateTime.to_iso8601(source.last_seen_at)})")
            true
          end
      end
    end
  end

  # Find event sources matching a URL
  defp find_venues_by_source_url(url, source_id) do
    # Ensure URL is not nil before querying
    if is_nil(url) do
      []
    else
      query = from es in EventSource,
        where: es.source_url == ^url and es.source_id == ^source_id,
        select: es

      Repo.all(query)
    end
  end

  # Check if an event source was recently updated
  defp recently_updated?(event_source) do
    case event_source.last_seen_at do
      nil ->
        # If last_seen_at is nil, consider it not recently updated
        false
      last_seen_at ->
        # Calculate the threshold date
        threshold_date = DateTime.utc_now() |> DateTime.add(-@skip_if_updated_within_days * 24 * 3600, :second)
        # Compare the last_seen_at with the threshold
        DateTime.compare(last_seen_at, threshold_date) == :gt
    end
  end

  # Reuse the venue fetching logic from the existing scraper
  def fetch_venues(nonce) do
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
    venues = String.split(body, "<a id=\"quizBlock-")
    |> Enum.drop(1) # Drop the first empty element
    |> Enum.map(fn block ->
      "<a id=\"quizBlock-" <> block
    end)
    |> Enum.map(&extract_venue_info/1)
    |> Enum.reject(&is_nil/1)

    venues
  end

  defp extract_venue_info(block) do
    case VenueExtractor.extract_venue_data(block) do
      {:ok, venue_data} -> venue_data
      _ -> nil
    end
  end
end

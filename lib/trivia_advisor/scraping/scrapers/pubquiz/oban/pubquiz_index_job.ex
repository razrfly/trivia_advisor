defmodule TriviaAdvisor.Scraping.Oban.PubquizIndexJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority(),
    unique: [period: 86400] # Run once per day

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Common
  alias TriviaAdvisor.Scraping.Oban.PubquizDetailJob
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Events.EventSource
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata

  # Days threshold for skipping recently updated events
  @skip_if_updated_within_days RateLimiter.skip_if_updated_within_days()

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting Pubquiz Index Job...")

    # Store args in process dictionary for access in other functions
    Process.put(:job_args, args)

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")
    Logger.info("🔍 Job args: #{inspect(args)}")
    Logger.info("🔍 Limit parameter: #{inspect(limit)}")

    # Check if we should force update all venues
    force_update = RateLimiter.force_update?(args)
    if force_update do
      Logger.info("⚠️ Force update enabled - will process ALL venues regardless of last update time")
    end

    # Check if we should force refresh all images
    force_refresh_images = RateLimiter.force_refresh_images?(args)
    if force_refresh_images do
      Logger.info("⚠️ Force image refresh enabled - will refresh ALL images regardless of existing state")
    end

    # Get the Pubquiz source
    source = Repo.get_by!(Source, name: "pubquiz")

    try do
      # Fetch city list and venues
      with {:ok, cities} <- Common.fetch_cities(),
           venues <- Common.fetch_venues_from_cities(cities),
           venues <- List.flatten(venues) do

        venues_count = length(venues)
        Logger.info("📊 Found #{venues_count} venues from pubquiz.pl")
        Logger.info("🔍 First venue sample: #{inspect(Enum.at(venues, 0))}")

        # Apply limit if specified
        venues_to_process = if limit, do: Enum.take(venues, limit), else: venues
        limited_count = length(venues_to_process)

        Logger.info("🔍 Venues to process count: #{limited_count}")
        if limited_count > 0 do
          Logger.info("🔍 First venue to process: #{inspect(Enum.at(venues_to_process, 0))}")
        end

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{venues_count} total)")
        end

        # Filter out venues that were recently updated
        {filtered_venues, skipped_venues} = filter_recently_updated_venues(venues_to_process, source.id)
        skipped_count = length(skipped_venues)

        if skipped_count > 0 do
          Logger.info("⏩ Skipping #{skipped_count} venues updated within the last #{@skip_if_updated_within_days} days")
        end

        # Schedule detail jobs using RateLimiter
        Logger.info("🔄 Calling RateLimiter.schedule_hourly_capped_jobs with #{length(filtered_venues)} venues")

        # Get force_update flag to pass to detail jobs
        force_update = RateLimiter.force_update?(args)

        # Get force_refresh_images flag to pass to detail jobs
        force_refresh_images = case Process.get(:job_args) do
          %{} = args ->
            # Get the flag value directly from args rather than using a helper
            flag_value = Map.get(args, "force_refresh_images", false) || Map.get(args, :force_refresh_images, false)
            # Log it explicitly for debugging
            Logger.info("🔍 DEBUG: Force refresh images flag extracted from index job args: #{inspect(flag_value)}")
            flag_value
          _ -> false
        end

        # Log it again for debugging
        Logger.info("🔍 DEBUG: Will pass force_refresh_images=#{inspect(force_refresh_images)} to detail jobs")

        # First, filter out venues with invalid URLs
        valid_venues = Enum.filter(filtered_venues, fn venue ->
          url = venue[:url]
          name = venue[:name] || "Unknown Venue"

          is_valid_url = is_binary(url) and String.trim(url) != ""

          if not is_valid_url do
            Logger.warning("⚠️ Skipping venue with invalid URL: #{inspect(name)}, URL: #{inspect(url)}")
          end

          is_valid_url
        end)

        # Log the count of valid venues
        valid_venues_count = length(valid_venues)
        Logger.info("📊 Found #{valid_venues_count} valid venues after filtering")

        # Schedule each venue individually
        jobs_scheduled = Enum.reduce(valid_venues, 0, fn venue, count ->
          # Get venue data with proper validation
          url = venue[:url]
          name = venue[:name] || "Unknown Venue"
          image_url = venue[:image_url]

          # Make sure URL starts with http
          url = if String.starts_with?(url, "http") do
            url
          else
            # Add https prefix if missing
            "https://#{url}"
          end

          # Convert venue with atom keys to string keys for consistency
          venue_with_string_keys = %{
            "name" => name,
            "url" => url,
            "image_url" => image_url
          }

          Logger.debug("🔄 Creating job for venue: #{inspect(venue_with_string_keys["name"])} with URL: #{inspect(venue_with_string_keys["url"])}")

          # Create the job args
          job_args = %{
            "venue_data" => venue_with_string_keys,
            "source_id" => source.id,
            "force_update" => force_update,  # Pass force_update flag to detail jobs
            "force_refresh_images" => force_refresh_images  # Pass force_refresh_images flag to detail jobs
          }

          # Create and schedule the job
          case Oban.insert(PubquizDetailJob.new(job_args)) do
            {:ok, _job} ->
              count + 1
            {:error, error} ->
              Logger.error("❌ Failed to schedule job: #{inspect(error)}")
              count
          end
        end)

        # Log the number of jobs scheduled
        Logger.info("📥 Scheduled #{jobs_scheduled} PubquizDetail jobs directly, skipped #{skipped_count} recent venues")

        # Create metadata for reporting
        metadata = %{
          "total_venues" => venues_count,
          "limited_to" => limited_count,
          "applied_limit" => limit,
          "enqueued_jobs" => jobs_scheduled,
          "skipped_venues" => skipped_count,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Update job metadata using JobMetadata helper
        JobMetadata.update_index_job(job_id, metadata)

        {:ok, %{venues_count: venues_count, enqueued_jobs: jobs_scheduled, skipped_venues: skipped_count}}
      else
        {:error, reason} ->
          Logger.error("❌ Failed to fetch venues: #{inspect(reason)}")
          # Update job metadata with error
          JobMetadata.update_error(job_id, reason)
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("❌ Error in PubquizIndexJob: #{Exception.message(e)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        # Update job metadata with error
        JobMetadata.update_error(job_id, Exception.message(e))
        {:error, e}
    end
  end

  # Filter out venues that were recently updated
  defp filter_recently_updated_venues(venues, source_id) do
    # Check if force update is enabled from the current job
    force_update = case Process.get(:job_args) do
      %{} = args -> RateLimiter.force_update?(args)
      _ -> false
    end

    if force_update do
      # If force_update is true, process all venues
      Logger.info("🔄 Force update enabled - processing ALL venues")
      {venues, []}
    else
      # Otherwise, filter based on last update time
      Enum.split_with(venues, fn venue ->
        should_process_venue?(venue, source_id)
      end)
    end
  end

  # Check if a venue should be processed based on its URL and last update time
  defp should_process_venue?(venue, source_id) do
    # The venue structure can have atom keys or string keys depending on context
    # We need to handle both cases
    url = venue[:url] || venue["url"]
    venue_name = venue[:name] || venue["name"]

    Logger.info("🔍 Checking venue URL: '#{url}' for venue: '#{venue_name}'")

    # Skip if no URL
    if is_nil(url) or url == "" do
      Logger.info("⏩ Venue has no URL, will process: #{inspect(venue_name)}")
      true
    else
      # Find existing event sources with this URL
      event_sources = find_venues_by_source_url(url, source_id)
      Logger.info("🔍 Found #{length(event_sources)} event sources for URL: #{url}")

      if event_sources != [] do
        # Log details about each found event source
        Enum.each(event_sources, fn es ->
          Logger.info("🔍 Found EventSource: id=#{es.id}, last_seen=#{es.last_seen_at}, source_url=#{es.source_url}")
        end)
      end

      case event_sources do
        [] ->
          # No existing venues with this URL, should process
          Logger.info("⏩ No existing events found for URL: #{url}")
          true
        event_sources ->
          # Check if any of these event sources were updated within the threshold
          not_recent = not Enum.any?(event_sources, fn event_source ->
            is_recent = recently_updated?(event_source)
            Logger.info("🔍 EventSource #{event_source.id} is_recent: #{is_recent}")
            is_recent
          end)

          if not_recent do
            Logger.info("⏩ Processing venue: #{venue_name} - no recent updates")
          else
            source = List.first(event_sources)
            Logger.info("⏩ SKIPPING venue: #{venue_name} - recently updated (#{DateTime.to_iso8601(source.last_seen_at)})")
          end

          not_recent
      end
    end
  end

  # Find event sources matching a URL
  defp find_venues_by_source_url(url, source_id) do
    query = from es in EventSource,
      where: es.source_url == ^url and es.source_id == ^source_id,
      select: es

    Repo.all(query)
  end

  # Check if an event source was recently updated
  defp recently_updated?(event_source) do
    # Calculate the threshold date
    threshold_date = DateTime.utc_now() |> DateTime.add(-@skip_if_updated_within_days * 24 * 3600, :second)

    # Compare the last_seen_at with the threshold
    result = case event_source.last_seen_at do
      nil -> false
      last_seen_at -> DateTime.compare(last_seen_at, threshold_date) == :gt
    end

    Logger.debug("⏩ Event last seen at: #{inspect(event_source.last_seen_at)}, threshold: #{inspect(threshold_date)}, is recent: #{result}")

    result
  end
end

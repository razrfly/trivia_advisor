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

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")
    Logger.info("🔍 Job args: #{inspect(args)}")
    Logger.info("🔍 Limit parameter: #{inspect(limit)}")

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

        enqueued_count = RateLimiter.schedule_hourly_capped_jobs(
          filtered_venues,
          PubquizDetailJob,
          fn venue ->
            Logger.debug("🔄 Creating job for venue: #{inspect(venue["name"])}")
            %{
              venue_data: venue,
              source_id: source.id
            }
          end
        )

        Logger.info("📥 Enqueued #{enqueued_count} PubquizDetail jobs with rate limiting, skipped #{skipped_count} recent venues")

        # Create metadata for reporting
        metadata = %{
          "total_venues" => venues_count,
          "limited_to" => limited_count,
          "applied_limit" => limit,
          "enqueued_jobs" => enqueued_count,
          "skipped_venues" => skipped_count,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Update job metadata using JobMetadata helper
        JobMetadata.update_index_job(job_id, metadata)

        {:ok, %{venues_count: venues_count, enqueued_jobs: enqueued_count, skipped_venues: skipped_count}}
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
    Enum.split_with(venues, fn venue ->
      should_process_venue?(venue, source_id)
    end)
  end

  # Check if a venue should be processed based on its URL and last update time
  defp should_process_venue?(venue, source_id) do
    # The venue structure has atom keys as shown in the logs:
    # %{name: "Pasibus", url: "https://pubquiz.pl/kategoria-produktu/bydgoszcz/pasibus/", image_url: "..."}
    url = venue[:url]
    venue_name = venue[:name]

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

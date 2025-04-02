defmodule TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob do
  use Oban.Worker, queue: :scraper

  require Logger
  import Ecto.Query

  # Aliases for Question One scraper functionality
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Events.EventSource

  # Days threshold for skipping recently updated venues
  @skip_if_updated_within_days RateLimiter.skip_if_updated_within_days()

  @base_url "https://questionone.com"
  @feed_url "#{@base_url}/venues/feed/"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting Question One Index Job...")

    # Store args in process dictionary for access in other functions
    Process.put(:job_args, args)

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Check if we should force update all venues
    force_update = RateLimiter.force_update?(args)
    if force_update do
      Logger.info("⚠️ Force update enabled - will process ALL venues regardless of last update time")
    end

    # Check for force_refresh_images flag - use direct extraction like Quizmeisters
    force_refresh_images = Map.get(args, "force_refresh_images", false) || Map.get(args, :force_refresh_images, false)
    if force_refresh_images do
      Logger.info("⚠️ Force image refresh enabled - will refresh ALL images in detail jobs")
      # Store in process dictionary for access in other functions
      Process.put(:force_refresh_images, true)
    else
      # Explicitly set to false to ensure it's not using a stale value
      Process.put(:force_refresh_images, false)
    end

    # Log the extracted value for debugging
    Logger.info("🔍 DEBUG: Force refresh images flag extracted from index job args: #{inspect(force_refresh_images)}")

    # Get the Question One source
    source = Repo.get_by!(Source, website_url: @base_url)

    # Call the existing scrape_feed function to get the event list
    case scrape_feed(1, []) do
      [] ->
        Logger.error("❌ No venues found in Question One feed")

        # Update job metadata with error
        error_metadata = %{
          "error" => "No venues found",
          "error_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Direct SQL update of the job's meta column
        Repo.update_all(
          from(j in "oban_jobs", where: j.id == ^job_id),
          set: [meta: error_metadata]
        )

        {:error, "No venues found"}

      venues when is_list(venues) ->
        # Log the number of venues found
        venue_count = length(venues)
        Logger.info("✅ Successfully fetched #{venue_count} venues from Question One feed")

        # Apply limit if specified
        venues_to_process = if limit, do: Enum.take(venues, limit), else: venues
        limited_count = length(venues_to_process)

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{venue_count} total)")
        end

        # Enqueue detail jobs for each venue using the RateLimiter
        {enqueued_count, skipped_count} = enqueue_detail_jobs(venues_to_process, source.id)

        Logger.info("🔢 RESULTS_COUNT: total=#{venue_count} limited=#{limited_count} enqueued=#{enqueued_count} skipped=#{skipped_count}")

        # Create metadata for reporting
        metadata = %{
          "total_venues" => venue_count,
          "limited_to" => limited_count,
          "enqueued_jobs" => enqueued_count,
          "skipped_venues" => skipped_count,
          "applied_limit" => limit,
          "source_id" => source.id,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Direct SQL update of the job's meta column
        Repo.update_all(
          from(j in "oban_jobs", where: j.id == ^job_id),
          set: [meta: metadata]
        )

        Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing, skipped #{skipped_count} recently updated venues")

        # Return success with venue count
        {:ok, %{venue_count: venue_count, enqueued_jobs: enqueued_count, skipped_venues: skipped_count, source_id: source.id}}

      {:error, reason} ->
        # Log the error
        Logger.error("❌ Failed to fetch Question One venues: #{inspect(reason)}")

        # Update job metadata with error
        error_metadata = %{
          "error" => inspect(reason),
          "error_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Direct SQL update of the job's meta column
        Repo.update_all(
          from(j in "oban_jobs", where: j.id == ^job_id),
          set: [meta: error_metadata]
        )

        # Return the error
        {:error, reason}
    end
  end

  # Enqueue detail jobs for each venue
  defp enqueue_detail_jobs(venues, source_id) do
    Logger.info("🔄 Checking and enqueueing detail jobs for #{length(venues)} venues...")

    # Check if force update is enabled from the current job
    force_update = case Process.get(:job_args) do
      %{} = args -> RateLimiter.force_update?(args)
      _ -> false
    end

    # Check if force refresh images is enabled - use the same direct extraction as Quizmeisters
    force_refresh_images = case Process.get(:job_args) do
      %{} = args ->
        # CRITICAL FIX: Ensure we get the right value and don't override it
        # Get the flag value directly from args rather than using a helper
        flag_value = Map.get(args, "force_refresh_images", false) || Map.get(args, :force_refresh_images, false)
        # Log it explicitly for debugging
        Logger.info("🔍 DEBUG: Force refresh images flag extracted from index job args: #{inspect(flag_value)}")
        flag_value
      _ -> false
    end

    # Log it again for debugging
    Logger.info("🔍 DEBUG: Will pass force_refresh_images=#{inspect(force_refresh_images)} to detail jobs")

    # Filter out venues that were recently updated (unless force_update is true)
    {venues_to_process, skipped_venues} = if force_update do
      # If force_update is true, process all venues
      Logger.info("🔄 Force update enabled - processing ALL venues")
      {venues, []}
    else
      # Otherwise, filter based on last update time
      Enum.split_with(venues, fn venue ->
        # Check if this venue (by URL) needs to be processed
        should_process_venue?(venue, source_id)
      end)
    end

    skipped_count = length(skipped_venues)

    if skipped_count > 0 do
      Logger.info("⏩ Skipping #{skipped_count} venues updated within the last #{@skip_if_updated_within_days} days")
    end

    # Use the RateLimiter to schedule jobs with a delay
    enqueued_count = RateLimiter.schedule_detail_jobs(
      venues_to_process,
      TriviaAdvisor.Scraping.Oban.QuestionOneDetailJob,
      fn venue ->
        # IMPORTANT: Use string keys for Oban job args to ensure they're preserved
        detail_args = %{
          "url" => Map.get(venue, :url),
          "title" => Map.get(venue, :title),
          "source_id" => source_id,
          "force_update" => force_update,  # Pass force_update flag to detail jobs
          "force_refresh_images" => force_refresh_images  # Pass force_refresh_images flag to detail jobs
        }

        # Log the first detail job args for debugging
        if venue == List.first(venues_to_process) do
          Logger.info("🔍 DEBUG: First detail job args: #{inspect(detail_args)}")
          Logger.info("🔍 DEBUG: force_refresh_images value in detail job: #{inspect(detail_args["force_refresh_images"])}")
        end

        detail_args
      end
    )

    {enqueued_count, skipped_count}
  end

  # Check if a venue should be processed based on its URL and last update time
  defp should_process_venue?(venue, source_id) do
    url = Map.get(venue, :url)

    # Find existing event sources with this URL
    case find_venues_by_source_url(url, source_id) do
      [] ->
        # No existing venues with this URL, should process
        true
      event_sources ->
        # Check if any of these event sources were updated within the threshold
        not Enum.any?(event_sources, fn event_source ->
          recently_updated?(event_source)
        end)
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
    case event_source.last_seen_at do
      nil -> false
      last_seen_at -> DateTime.compare(last_seen_at, threshold_date) == :gt
    end
  end

  # The following functions are adapted from the Question One scraper
  # to avoid modifying the original code

  defp scrape_feed(page, acc) do
    url = if page == 1, do: @feed_url, else: "#{@feed_url}?paged=#{page}"
    Logger.info("Fetching page #{page}: #{url}")

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case parse_feed(body) do
          [] ->
            Logger.info("No venues found on page #{page}, stopping")
            acc
          venues ->
            Logger.info("Found #{length(venues)} venues on page #{page}")
            venues |> Enum.each(&log_venue/1)
            # Continue to next page
            scrape_feed(page + 1, acc ++ venues)
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.info("Reached end at page #{page}")
        acc

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} on page #{page}")
        acc

      {:error, error} ->
        Logger.error("Error fetching page #{page}: #{inspect(error)}")
        acc
    end
  end

  defp parse_feed(body) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        document
        |> Floki.find("item")
        |> Enum.map(fn item ->
          %{
            title: item |> Floki.find("title") |> Floki.text() |> String.trim() |> HtmlEntities.decode(),
            url: item |> Floki.find("link") |> Floki.text() |> String.trim() |> clean_url()
          }
        end)
      {:error, reason} ->
        Logger.error("Failed to parse feed: #{inspect(reason)}")
        []
    end
  end

  defp clean_url(url) do
    url
    |> String.split("?")
    |> List.first()
    |> String.trim()
  end

  defp log_venue(%{title: title, url: url}) do
    Logger.info("""
    Found Venue:
      Title: #{title}
      URL: #{url}
    """)
  end
end

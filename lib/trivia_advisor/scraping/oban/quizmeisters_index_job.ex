defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger
  import Ecto.Query  # Add this for database queries

  # Aliases for the Quizmeisters scraper functionality
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Events.EventSource  # Add this for venue URL checking

  # Days threshold for skipping recently updated venues
  @skip_if_updated_within_days RateLimiter.skip_if_updated_within_days()

  # Strict timeout values to prevent hanging requests
  @http_options [
    follow_redirect: true,
    timeout: 15_000,        # 15 seconds for connect timeout
    recv_timeout: 15_000,   # 15 seconds for receive timeout
    hackney: [pool: false]  # Don't use connection pooling for scrapers
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting Quizmeisters Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Get the Quizmeisters source
    source = Repo.get_by!(Source, website_url: "https://quizmeisters.com")

    # Call the existing fetch_venues function to get the venue list
    case fetch_venues() do
      {:ok, venues} ->
        # Log the number of venues found
        venue_count = length(venues)
        Logger.info("✅ Successfully fetched #{venue_count} venues from Quizmeisters")

        # Apply limit if specified
        venues_to_process = if limit, do: Enum.take(venues, limit), else: venues
        limited_count = length(venues_to_process)

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{venue_count} total)")
        end

        # Enqueue detail jobs for each venue with rate limiting
        {enqueued_count, skipped_count} = enqueue_detail_jobs_with_rate_limiting(venues_to_process, source.id)
        Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing, skipped #{skipped_count} recently updated venues")

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

        # Return success with venue count
        {:ok, %{venue_count: venue_count, enqueued_jobs: enqueued_count, skipped_venues: skipped_count, source_id: source.id}}

      {:error, reason} ->
        # Log the error
        Logger.error("❌ Failed to fetch Quizmeisters venues: #{inspect(reason)}")

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

  # Enqueue detail jobs for each venue with rate limiting
  defp enqueue_detail_jobs_with_rate_limiting(venues, source_id) do
    Logger.info("🔄 Checking and enqueueing detail jobs for #{length(venues)} venues...")

    # Filter out venues that were recently updated
    {venues_to_process, skipped_venues} = Enum.split_with(venues, fn venue ->
      # Check if this venue (by URL) needs to be processed
      should_process_venue?(venue, source_id)
    end)

    skipped_count = length(skipped_venues)

    if skipped_count > 0 do
      Logger.info("⏩ Skipping #{skipped_count} venues updated within the last #{@skip_if_updated_within_days} days")
    end

    # Use the RateLimiter to schedule jobs with a delay
    enqueued_count = RateLimiter.schedule_detail_jobs(
      venues_to_process,
      TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob,
      fn venue ->
        %{
          venue: venue,
          source_id: source_id
        }
      end
    )

    {enqueued_count, skipped_count}
  end

  # Check if a venue should be processed based on its URL and last update time
  defp should_process_venue?(venue, source_id) do
    # Use the venue URL to check if it needs processing
    url = Map.get(venue, "url")

    # Skip if no URL
    if is_nil(url) or url == "" do
      Logger.warning("⚠️ Venue has no URL, will process: #{inspect(venue["name"])}")
      true
    else
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

  # The following function is copied from the existing Quizmeisters scraper
  # to avoid modifying the original code
  defp fetch_venues do
    api_url = "https://storerocket.io/api/user/kDJ3BbK4mn/locations"

    # Create a task with timeout for the API request
    task = Task.async(fn ->
      case HTTPoison.get(api_url, [], @http_options) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"results" => %{"locations" => locations}}} when is_list(locations) ->
              {:ok, locations}

            {:error, reason} ->
              Logger.error("Failed to parse JSON response: #{inspect(reason)}")
              {:error, "Failed to parse JSON response"}

            _ ->
              Logger.error("Unexpected response format")
              {:error, "Unexpected response format"}
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          Logger.error("HTTP #{status}: Failed to fetch venues")
          {:error, "HTTP #{status}"}

        {:error, %HTTPoison.Error{reason: :timeout}} ->
          Logger.error("Timeout fetching Quizmeisters venues")
          {:error, "HTTP request timeout"}

        {:error, %HTTPoison.Error{reason: :connect_timeout}} ->
          Logger.error("Connection timeout fetching Quizmeisters venues")
          {:error, "HTTP connection timeout"}

        {:error, reason} ->
          Logger.error("Request failed: #{inspect(reason)}")
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end)

    # Wait for the task with a hard timeout
    case Task.yield(task, 30_000) || Task.shutdown(task) do
      {:ok, result} -> result
      nil ->
        Logger.error("Task timeout when fetching Quizmeisters venues")
        {:error, "Task timeout"}
    end
  end
end

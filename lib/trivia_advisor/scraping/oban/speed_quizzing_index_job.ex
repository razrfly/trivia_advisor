defmodule TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger
  import Ecto.Query

  # Aliases for the SpeedQuizzing scraper functionality
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Events.EventSource
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Events.Event
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata

  # Days threshold for skipping recently updated events
  @skip_if_updated_within_days RateLimiter.skip_if_updated_within_days()

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id} = _job) do
    Logger.info("🔄 Starting SpeedQuizzing Index Job...")

    # Store args in process dictionary for access in other functions
    Process.put(:job_args, args)

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Check if we should force update all venues
    force_update = RateLimiter.force_update?(args)
    if force_update do
      Logger.info("⚠️ Force update enabled - will process ALL venues regardless of last update time")
    end

    # Get the SpeedQuizzing source
    source = Repo.get_by!(Source, slug: "speed-quizzing")

    # Call the existing fetch_events_json function to get the event list
    case fetch_events_json() do
      {:ok, events} ->
        # Log the number of events found
        event_count = length(events)
        Logger.info("✅ Successfully fetched #{event_count} events from SpeedQuizzing index page")

        # Apply limit if specified
        events_to_process = if limit, do: Enum.take(events, limit), else: events
        limited_count = length(events_to_process)

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} events (out of #{event_count} total)")
        end

        # Enqueue detail jobs for each event
        {enqueued_count, skipped_count} = enqueue_detail_jobs(events_to_process, source.id)

        # Add to application log with distinct prefix
        Logger.info("🔢 RESULTS_COUNT: total=#{event_count} limited=#{limited_count} enqueued=#{enqueued_count} skipped=#{skipped_count}")

        # Create metadata for reporting
        metadata = %{
          "total_events" => event_count,
          "limited_to" => limited_count,
          "enqueued_jobs" => enqueued_count,
          "skipped_events" => skipped_count,
          "applied_limit" => limit,
          "source_id" => source.id,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Update job metadata
        JobMetadata.update_index_job(job_id, metadata)

        Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing, skipped #{skipped_count} recent events")

        # Return success
        {:ok, %{event_count: event_count, enqueued_jobs: enqueued_count, skipped_jobs: skipped_count, source_id: source.id}}

      {:error, reason} ->
        # Log the error
        Logger.error("❌ Failed to fetch SpeedQuizzing events: #{inspect(reason)}")

        # Update job metadata with error
        JobMetadata.update_error(job_id, reason)

        # Return the error
        {:error, reason}
    end
  end

  # Enqueue detail jobs for each event
  defp enqueue_detail_jobs(events, source_id) do
    Logger.info("🔄 Checking and enqueueing detail jobs for #{length(events)} events...")

    # Check if force update is enabled from the current job
    force_update = case Process.get(:job_args) do
      %{} = args -> RateLimiter.force_update?(args)
      _ -> false
    end

    # Filter out events that were recently updated (unless force_update is true)
    {events_to_process, skipped_events} = if force_update do
      # If force_update is true, process all events
      Logger.info("🔄 Force update enabled - processing ALL events")
      {events, []}
    else
      # Otherwise, filter based on last update time
      Enum.split_with(events, fn event ->
        # Check if this event (by coordinates) needs to be processed
        should_process_event?(event, source_id)
      end)
    end

    skipped_count = length(skipped_events)

    if skipped_count > 0 do
      Logger.info("⏩ Skipping #{skipped_count} events updated within the last #{@skip_if_updated_within_days} days")
    end

    # Use the RateLimiter to schedule jobs with a delay
    enqueued_count = RateLimiter.schedule_hourly_capped_jobs(
      events_to_process,
      TriviaAdvisor.Scraping.Oban.SpeedQuizzingDetailJob,
      fn event ->
        %{
          event_id: Map.get(event, "event_id") || Map.get(event, "id"),
          source_id: source_id,
          lat: Map.get(event, "lat"),
          lng: Map.get(event, "lon"),
          force_update: force_update  # Pass force_update flag to detail jobs
        }
      end
    )

    {enqueued_count, skipped_count}
  end

  # Check if an event should be processed based on last update time
  defp should_process_event?(event, source_id) do
    # Skip events with unusable day_of_week information if we can determine it
    day_info = Map.get(event, "day_of_week")
    if not is_nil(day_info) and day_info == "Unknown" do
      Logger.info("⏩ Skipping event ID #{Map.get(event, "id")} because day_of_week is Unknown")
      false
    else
      # Get latitude and longitude
      lat = Map.get(event, "lat")
      lng = Map.get(event, "lon")

      # If no coordinates, we should process it
      if is_nil(lat) || is_nil(lng) || lat == "" || lng == "" do
        true
      else
        # Find existing venues/events near these coordinates
        case find_events_near_coordinates(lat, lng, source_id) do
          [] ->
            # No existing events nearby, should process
            true
          events_sources ->
            # Check if any of these events were updated within the threshold
            not Enum.any?(events_sources, fn event_source ->
              recently_updated?(event_source)
            end)
        end
      end
    end
  end

  # Find events near coordinates
  defp find_events_near_coordinates(lat, lng, source_id) do
    # Parse coordinates to float
    {lat_float, _} = Float.parse(lat)
    {lng_float, _} = Float.parse(lng)

    # Look for venues near these coordinates within 50 meters
    query = from v in Venue,
      join: e in Event, on: e.venue_id == v.id,
      join: es in EventSource, on: es.event_id == e.id and es.source_id == ^source_id,
      where: fragment("ST_DWithin(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, 50)", ^lng_float, ^lat_float, v.longitude, v.latitude),
      select: es

    Repo.all(query)
  end

  # Check if an event was recently updated
  defp recently_updated?(event_source) do
    # Calculate the threshold date
    threshold_date = DateTime.utc_now() |> DateTime.add(-@skip_if_updated_within_days * 24 * 3600, :second)

    # Compare the last_seen_at with the threshold
    case event_source.last_seen_at do
      nil -> false
      last_seen_at -> DateTime.compare(last_seen_at, threshold_date) == :gt
    end
  end

  # The following functions are copied from the existing SpeedQuizzing scraper
  # to avoid modifying the original code

  defp fetch_events_json do
    index_url = "https://www.speedquizzing.com/find/"

    case HTTPoison.get(index_url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, document} <- Floki.parse_document(body),
             {:ok, json} <- extract_events_json(document),
             {:ok, events} <- parse_events_json(json) do
          {:ok, events}
        else
          {:error, reason} ->
            Logger.error("Failed to extract or parse events JSON: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status}: Failed to fetch index page")
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp extract_events_json(document) do
    script_content = document
    |> Floki.find("script:not([src])")
    |> Enum.map(&Floki.raw_html/1)
    |> Enum.find(fn html ->
      String.contains?(html, "var events = JSON.parse(")
    end)

    case script_content do
      nil ->
        {:error, "Events JSON not found in page"}
      content ->
        # Extract the JSON string within the single quotes
        regex = ~r/var events = JSON\.parse\('(.+?)'\)/s
        case Regex.run(regex, content) do
          [_, json_str] ->
            # Unescape single quotes and other characters
            unescaped = json_str
            |> String.replace("\\'", "'")
            |> String.replace("\\\\", "\\")
            {:ok, unescaped}
          _ ->
            {:error, "Failed to extract JSON string"}
        end
    end
  end

  defp parse_events_json(json_str) do
    case Jason.decode(json_str) do
      {:ok, events} when is_list(events) ->
        # Add a source_id field to each event for easier tracking
        events = Enum.map(events, fn event ->
          Map.put(event, "source_id", "speed-quizzing")
        end)
        {:ok, events}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("JSON decode error: #{Exception.message(error)}")
        Logger.error("Problematic JSON: #{json_str}")
        {:error, "JSON parsing error: #{Exception.message(error)}"}

      error ->
        Logger.error("Unexpected error parsing JSON: #{inspect(error)}")
        {:error, "Unexpected JSON parsing error"}
    end
  end
end

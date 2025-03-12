defmodule TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger
  import Ecto.Query

  # Aliases for the SpeedQuizzing scraper functionality
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Events.{Event, EventSource}
  alias TriviaAdvisor.Locations.Venue

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting SpeedQuizzing Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Check if a max_jobs parameter is specified to limit production runs
    max_jobs = Map.get(args, "max_jobs")

    # Get the SpeedQuizzing source
    source = Repo.get_by!(Source, slug: "speed-quizzing")

    # Call the existing fetch_events_json function to get the event list
    case fetch_events_json() do
      {:ok, events} ->
        # Log the number of events found
        event_count = length(events)
        Logger.info("✅ Successfully fetched #{event_count} events from SpeedQuizzing index page")

        # Apply limit or max_jobs if specified (prioritize limit for backwards compatibility)
        events_to_process = cond do
          limit -> Enum.take(events, limit)
          max_jobs -> Enum.take(events, max_jobs)
          true -> events
        end
        limited_count = length(events_to_process)

        # Log appropriate message based on which limitation is applied
        cond do
          limit ->
            Logger.info("🧪 Testing mode: Limited to #{limited_count} events (out of #{event_count} total)")
          max_jobs ->
            Logger.info("⚙️ Production limit: Processing #{limited_count} events (out of #{event_count} total)")
          true ->
            :ok
        end

        # Enqueue detail jobs for each event
        {enqueued_count, skipped_count} = enqueue_detail_jobs(events_to_process, source.id)
        Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing")
        Logger.info("🔄 Skipped #{skipped_count} recently updated events")

        # Return success with event count
        {:ok, %{event_count: event_count, enqueued_jobs: enqueued_count, skipped_jobs: skipped_count, source_id: source.id}}

      {:error, reason} ->
        # Log the error
        Logger.error("❌ Failed to fetch SpeedQuizzing events: #{inspect(reason)}")

        # Return the error
        {:error, reason}
    end
  end

  # Enqueue detail jobs for each event, now with filtering for recently updated venues
  defp enqueue_detail_jobs(events, source_id) do
    Logger.info("🔄 Checking #{length(events)} events for recent updates...")

    # Split events into those to process and those to skip
    {events_to_process, events_to_skip} = Enum.split_with(events, fn event ->
      # Check if this event should be processed (not recently updated)
      should_process_event?(event, source_id)
    end)

    Logger.info("🔄 Enqueueing detail jobs for #{length(events_to_process)} events...")

    # Use the RateLimiter to schedule jobs with a delay
    enqueued_count = RateLimiter.schedule_detail_jobs(
      events_to_process,
      TriviaAdvisor.Scraping.Oban.SpeedQuizzingDetailJob,
      fn event ->
        %{
          event_id: Map.get(event, "event_id"),
          source_id: source_id,
          lat: Map.get(event, "lat"),
          lng: Map.get(event, "lon")
        }
      end
    )

    {enqueued_count, length(events_to_skip)}
  end

  # Helper function to determine if we should process an event
  # Skips events with venues that have been updated recently
  defp should_process_event?(event, source_id) do
    # Get latitude and longitude from the event
    event_lat = Map.get(event, "lat") |> String.to_float()
    event_lng = Map.get(event, "lon") |> String.to_float()

    # Find any venues near these coordinates that might be associated with this event
    venues = find_venues_near_coordinates(event_lat, event_lng)

    # If there are no nearby venues, we need to process this event to create the venue
    if Enum.empty?(venues) do
      true
    else
      # Check if any venue has a recently updated event source
      cutoff_date = DateTime.utc_now() |> DateTime.add(-1 * RateLimiter.skip_if_updated_within_days() * 24 * 60 * 60, :second)

      # We should process the event if we don't have any recently updated sources
      venues
      |> Enum.all?(fn venue ->
        # Get venue ID
        venue_id = venue.id

        # Find event sources associated with this venue and the current source
        recent_sources = from(e in Event,
          join: es in EventSource, on: es.event_id == e.id,
          where: e.venue_id == ^venue_id and es.source_id == ^source_id and es.last_seen_at > ^cutoff_date,
          select: es
        ) |> Repo.aggregate(:count)

        # True if no recent sources (meaning we should process), false otherwise
        recent_sources == 0
      end)
    end
  end

  # Find venues near specific coordinates (within approximately 100 meters)
  defp find_venues_near_coordinates(lat, lng) do
    # Use ST_Distance to find venues within 0.1 km (about 100 meters)
    # This is a rough proximity check that could be refined
    from(v in Venue,
      where: fragment(
        "ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography) < 100",
        ^lng, ^lat, type(v.lng, :float), type(v.lat, :float)
      )
    )
    |> Repo.all()
  end

  # Fetches the JSON data for all events from the SpeedQuizzing API
  defp fetch_events_json do
    # URL for the SpeedQuizzing API that returns all events
    url = "https://hub.speed-quizzing.com/api/events"

    # Attempt to fetch the JSON data
    case Finch.build(:get, url) |> Finch.request(TriviaAdvisor.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        # Parse the JSON body
        case Jason.decode(body) do
          {:ok, json_data} ->
            # Extract data array from the JSON response
            data = Map.get(json_data, "data", [])
            {:ok, data}

          {:error, error} ->
            Logger.error("❌ Failed to parse SpeedQuizzing JSON response: #{inspect(error)}")
            {:error, "Failed to parse JSON: #{inspect(error)}"}
        end

      {:ok, %Finch.Response{status: status}} ->
        Logger.error("❌ SpeedQuizzing API returned non-200 status: #{status}")
        {:error, "API returned status #{status}"}

      {:error, error} ->
        Logger.error("❌ Failed to fetch SpeedQuizzing events data: #{inspect(error)}")
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  # Extracts event data from the HTML content
  defp extract_events(html) do
    {:error, "This function is deprecated in favor of the JSON API approach"}
  end

  # Parses the HTML from the response body
  defp parse_html(response_body) do
    {:error, "This function is deprecated in favor of the JSON API approach"}
  end
end

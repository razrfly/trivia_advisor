defmodule TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob do
  use Oban.Worker, queue: :default

  require Logger
  import Ecto.Query

  # Configurable threshold for how recent an event update needs to be to skip processing
  # This can be moved to application config later for all scrapers
  @skip_if_updated_within_days 5

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

  # Helper function to determine if an event should be processed based on recent updates
  defp should_process_event?(event, source_id) do
    # Skip processing if we have no coordinates - need them to find venues
    lat = Map.get(event, "lat")
    lng = Map.get(event, "lng") || Map.get(event, "lon")

    if is_nil(lat) or is_nil(lng) do
      true # Process events without coordinates - we can't match them reliably
    else
      # Try to find matching venues by location
      venues = find_venues_near_coordinates(lat, lng)

      if Enum.empty?(venues) do
        true # No matching venue found, so process this event
      else
        # Check if any of these venues have events from this source updated recently
        venue_ids = Enum.map(venues, & &1.id)

        # Calculate cutoff date (e.g., 5 days ago)
        cutoff_date = DateTime.add(DateTime.utc_now(), -1 * @skip_if_updated_within_days * 24 * 60 * 60, :second)

        # Query to find if any matching events exist and were updated in last N days
        recent_event_sources =
          from(es in EventSource,
            join: e in Event, on: es.event_id == e.id,
            where: e.venue_id in ^venue_ids,
            where: es.source_id == ^source_id,
            where: es.last_seen_at >= ^cutoff_date,
            limit: 1
          )
          |> Repo.all()

        # If no recent event sources, we should process this event
        Enum.empty?(recent_event_sources)
      end
    end
  end

  # Function to find venues near given coordinates
  defp find_venues_near_coordinates(lat, lng) do
    # Convert strings to floats if needed
    {lat, lng} = {ensure_float(lat), ensure_float(lng)}

    # Use a small radius (e.g., 50 meters) to find matching venues
    # This query uses PostGIS ST_Distance instead of <@> operator
    query =
      from(v in Venue,
        where: not is_nil(v.latitude) and not is_nil(v.longitude),
        where: fragment(
          "ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326), ST_SetSRID(ST_MakePoint(?, ?), 4326)) < ?",
          v.longitude, v.latitude, ^lng, ^lat, 0.05
        ),
        limit: 5
      )

    Repo.all(query)
  end

  # Helper to ensure we have floats
  defp ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end
  defp ensure_float(value) when is_float(value), do: value
  defp ensure_float(value) when is_integer(value), do: value * 1.0
  defp ensure_float(_), do: nil

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

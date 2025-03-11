defmodule TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob do
  use Oban.Worker, queue: :default

  require Logger

  # Aliases for the SpeedQuizzing scraper functionality
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.RateLimiter

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting SpeedQuizzing Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

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
        enqueued_count = enqueue_detail_jobs(events_to_process, source.id)
        Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing")

        # Return success with event count
        {:ok, %{event_count: event_count, enqueued_jobs: enqueued_count, source_id: source.id}}

      {:error, reason} ->
        # Log the error
        Logger.error("❌ Failed to fetch SpeedQuizzing events: #{inspect(reason)}")

        # Return the error
        {:error, reason}
    end
  end

  # Enqueue detail jobs for each event
  defp enqueue_detail_jobs(events, source_id) do
    Logger.info("🔄 Enqueueing detail jobs for #{length(events)} events...")

    # Use the RateLimiter to schedule jobs with a delay
    RateLimiter.schedule_detail_jobs(
      events,
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

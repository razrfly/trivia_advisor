defmodule TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.Scraper do
  @moduledoc """
  Scraper for SpeedQuizzing venues and events.
  """

  alias TriviaAdvisor.Scraping.{ScrapeLog, Source}
  alias TriviaAdvisor.Repo
  # Comment out aliases that aren't needed for the first step
  # alias TriviaAdvisor.Locations.VenueStore
  # alias TriviaAdvisor.Events.EventStore
  # alias TriviaAdvisor.Services.GooglePlaceImageStore
  require Logger

  @base_url "https://www.speedquizzing.com"
  @index_url "#{@base_url}/find/"
  @version "1.0.0"

  @doc """
  Main entry point for the scraper.
  """
  def run do
    Logger.info("Starting SpeedQuizzing scraper")
    source = Repo.get_by!(Source, slug: "speed-quizzing")
    start_time = DateTime.utc_now()

    case ScrapeLog.create_log(source) do
      {:ok, log} ->
        try do
          Logger.info("🔍 Fetching SpeedQuizzing events from index page...")

          case fetch_events_json() do
            {:ok, events} ->
              event_count = length(events)
              Logger.info("✅ Successfully scraped #{event_count} events from index page")

              # Log events instead of processing them
              Enum.each(events, &log_event/1)

              # Comment out event processing for now
              # processed_events = events
              # |> Enum.map(&process_event(&1, source))
              # |> Enum.reject(&is_nil/1)
              #
              # successful_count = length(processed_events)

              # Update the scrape log with success info
              ScrapeLog.update_log(log, %{
                success: true,
                event_count: event_count, # Use total count since we're not processing yet
                metadata: %{
                  total_events: event_count,
                  # processed_events: successful_count,
                  events: events,
                  started_at: DateTime.to_iso8601(start_time),
                  completed_at: DateTime.to_iso8601(DateTime.utc_now()),
                  scraper_version: @version
                }
              })

              {:ok, events}

            {:error, reason} ->
              Logger.error("❌ Failed to fetch events: #{inspect(reason)}")
              ScrapeLog.log_error(log, reason)
              {:error, reason}
          end
        rescue
          e ->
            Logger.error("❌ Scraper failed: #{Exception.message(e)}")
            ScrapeLog.log_error(log, e)
            {:error, e}
        end

      {:error, reason} ->
        Logger.error("Failed to create scrape log: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Comment out the processing functions for now
  # # Process an individual event and create venue and event records
  # defp process_event(event, source) do
  #   try do
  #     # Log the event for debugging/display
  #     log_event(event)
  #
  #     # Extract venue information
  #     venue_attrs = %{
  #       name: Map.get(event, "venue", "Unknown Venue"),
  #       address: extract_address(event),
  #       lat: Map.get(event, "lat"),
  #       lng: Map.get(event, "lon")
  #     }
  #
  #     # Only process venues with coordinates
  #     if venue_attrs.lat != "" && venue_attrs.lng != "" do
  #       case VenueStore.process_venue(venue_attrs) do
  #         {:ok, venue} ->
  #           Logger.info("✅ Successfully processed venue: #{venue.name}")
  #
  #           # Check if we should fetch Google Place images
  #           venue = GooglePlaceImageStore.maybe_update_venue_images(venue)
  #
  #           # Create event data
  #           event_data = %{
  #             raw_title: "SpeedQuizzing at #{venue.name}",
  #             name: venue.name,
  #             time_text: format_event_time(event),
  #             description: "SpeedQuizzing event at #{venue.name}",
  #             fee_text: "Contact venue for details",
  #             source_url: "#{@base_url}/find/?id=#{Map.get(event, "event_id")}",
  #             performer_id: nil,
  #             hero_image_url: nil
  #           }
  #
  #           case EventStore.process_event(venue, event_data, source.id) do
  #             {:ok, event_record} ->
  #               Logger.info("✅ Successfully created event for venue: #{venue.name}")
  #               {venue, event_record}
  #             {:error, reason} ->
  #               Logger.error("❌ Failed to create event: #{inspect(reason)}")
  #               nil
  #           end
  #
  #         {:error, reason} ->
  #           Logger.error("❌ Failed to process venue: #{inspect(reason)}")
  #           nil
  #       end
  #     else
  #       Logger.info("⚠️ Skipping event with no coordinates")
  #       nil
  #     end
  #   rescue
  #     e ->
  #       Logger.error("""
  #       ❌ Failed to process event
  #       Error: #{Exception.message(e)}
  #       Event Data: #{inspect(event)}
  #       """)
  #       nil
  #   end
  # end
  #
  # # Extract formatted address from event data
  # defp extract_address(event) do
  #   [
  #     Map.get(event, "address", ""),
  #     Map.get(event, "city", ""),
  #     Map.get(event, "state", ""),
  #     Map.get(event, "postcode", "")
  #   ]
  #   |> Enum.filter(&(is_binary(&1) and &1 != ""))
  #   |> Enum.join(", ")
  # end
  #
  # # Format the event time from event data
  # defp format_event_time(event) do
  #   day = Map.get(event, "day", "")
  #   time = Map.get(event, "time", "20:00")
  #
  #   "#{day} #{time}"
  # end

  defp fetch_events_json do
    case HTTPoison.get(@index_url, [], follow_redirect: true) do
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

  defp log_event(event) do
    # Format the event details for logging
    event_id = Map.get(event, "event_id", "unknown")
    date = Map.get(event, "date", "unknown")
    day = Map.get(event, "day", "unknown")
    lat = Map.get(event, "lat", "")
    lon = Map.get(event, "lon", "")

    location = if lat != "" and lon != "" do
      "Lat: #{lat}, Lon: #{lon}"
    else
      "No coordinates"
    end

    Logger.info("""
    📅 Event:
      ID: #{event_id}
      Date: #{date} (#{day})
      Location: #{location}
    """)
  end
end

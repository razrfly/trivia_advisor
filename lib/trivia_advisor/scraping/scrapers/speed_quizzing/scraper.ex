defmodule TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.Scraper do
  @moduledoc """
  Scraper for SpeedQuizzing venues and events.
  """

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.{ScrapeLog, Source}
  alias TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.VenueExtractor
  # Comment out aliases that aren't needed for the first step
  # alias TriviaAdvisor.Locations.VenueStore
  # alias TriviaAdvisor.Events.EventStore
  # alias TriviaAdvisor.Services.GooglePlaceImageStore

  @base_url "https://www.speedquizzing.com"
  @index_url "#{@base_url}/find/"
  @version "1.0.0"
  @max_event_details 500  # Temporarily reduced from 50 to 5 for testing

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

              # Process a limited number of events to avoid overloading
              events_to_process = Enum.take(events, @max_event_details)
              processed_count = length(events_to_process)

              Logger.info("🔍 Fetching details for #{processed_count} events...")

              # Fetch and process venue details for each event
              venue_details = events_to_process
              |> Enum.map(fn event ->
                event_id = Map.get(event, "event_id")
                case VenueExtractor.extract(event_id) do
                  {:ok, venue_data} ->
                    # Add coordinates from the index data
                    venue_data = Map.merge(venue_data, %{
                      lat: Map.get(event, "lat"),
                      lng: Map.get(event, "lon")
                    })
                    # Log the venue and event details
                    log_venue_details(venue_data)
                    {:ok, venue_data}
                  {:error, reason} ->
                    Logger.error("❌ Failed to extract venue details for event ID #{event_id}: #{inspect(reason)}")
                    {:error, reason}
                end
              end)
              |> Enum.filter(fn result -> match?({:ok, _}, result) end)
              |> Enum.map(fn {:ok, data} -> data end)

              successful_venues_count = length(venue_details)

              Logger.info("✅ Successfully fetched details for #{successful_venues_count} venues out of #{processed_count} attempted")

              # Update the scrape log with success info
              ScrapeLog.update_log(log, %{
                success: true,
                event_count: event_count,
                metadata: %{
                  total_events: event_count,
                  processed_events: processed_count,
                  successful_venue_details: successful_venues_count,
                  venue_details: venue_details,
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

  # Commented out as it's no longer used
  # defp log_event(event) do
  #   # Format the event details for logging
  #   event_id = Map.get(event, "event_id", "unknown")
  #   date = Map.get(event, "date", "unknown")
  #   day = Map.get(event, "day", "unknown")
  #   lat = Map.get(event, "lat", "")
  #   lon = Map.get(event, "lon", "")

  #   location = if lat != "" and lon != "" do
  #     "Lat: #{lat}, Lon: #{lon}"
  #   else
  #     "No coordinates"
  #   end

  #   Logger.info("""
  #   📅 Event:
  #     ID: #{event_id}
  #     Date: #{date} (#{day})
  #     Location: #{location}
  #   """)
  # end

  defp log_venue_details(venue_data) do
    # Parse day of week
    day_of_week = case venue_data.day_of_week do
      "Monday" -> 1
      "Tuesday" -> 2
      "Wednesday" -> 3
      "Thursday" -> 4
      "Friday" -> 5
      "Saturday" -> 6
      "Sunday" -> 7
      _ -> nil
    end

    # Parse start time
    start_time = if venue_data.start_time == "00:00" or is_nil(venue_data.start_time) do
      nil
    else
      case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time(venue_data.start_time) do
        {:ok, time} -> time
        _ -> venue_data.start_time
      end
    end

    # Create standardized venue data
    standardized_venue_data = %{
      raw_title: venue_data.event_title,
      title: venue_data.venue_name,
      address: venue_data.address,
      time_text: "#{venue_data.day_of_week} #{venue_data.start_time}",
      day_of_week: day_of_week,
      start_time: start_time,
      frequency: :weekly,
      fee_text: venue_data.description,
      phone: nil,
      website: venue_data.event_url,
      description: venue_data.description,
      hero_image_url: nil,
      url: venue_data.event_url,
      postcode: venue_data.postcode,
      performer: venue_data.performer
    }

    # Log venue details using VenueHelpers
    TriviaAdvisor.Scraping.Helpers.VenueHelpers.log_venue_details(standardized_venue_data)
  end
end

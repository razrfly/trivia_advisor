defmodule TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.Scraper do
  @moduledoc """
  Scraper for SpeedQuizzing venues and events.

  DEPRECATED: This legacy scraper is deprecated in favor of Oban jobs.
  Please use TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob instead.
  """

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.VenueExtractor
  # Enable aliases for venue and event processing
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Events.Performer
  alias TriviaAdvisor.Services.GooglePlaceImageStore
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

  @base_url "https://www.speedquizzing.com"
  @index_url "#{@base_url}/find/"
  @version "1.0.0"
  @max_event_details 1500  # Changed from 10 back to 50 for production use

  @doc """
  Main entry point for the scraper.

  DEPRECATED: Please use TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob instead.
  """
  def run do
    Logger.warning("⚠️ DEPRECATED: This legacy scraper is deprecated. Please use TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob instead.")
    Logger.info("Starting SpeedQuizzing scraper")
    source = Repo.get_by!(Source, slug: "speed-quizzing")
    start_time = DateTime.utc_now()

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

                # Process venue and create event
                result = process_venue_and_event(venue_data, source)
                # Extract the event data for JSON serialization
                event_data = case result do
                  {:ok, %{venue: _venue, event: _event}} ->
                    # Already in the right format, extract data
                    extract_event_data(result)
                  {:ok, event} ->
                    # Direct event result, wrap it
                    extract_event_data({:ok, %{venue: nil, event: event}})
                  other ->
                    # Handle other cases
                    extract_event_data(other)
                end
                event_data
              {:error, reason} ->
                Logger.error("❌ Failed to extract venue details for event ID #{event_id}: #{inspect(reason)}")
                %{error: inspect(reason)}
            end
          end)
          |> Enum.filter(fn result -> !Map.has_key?(result, :error) end)

          successful_venues_count = length(venue_details)

          Logger.info("✅ Successfully processed #{successful_venues_count} venues out of #{processed_count} attempted")

          # Log scrape summary
          Logger.info("""
          📊 SpeedQuizzing Scrape Summary:
          - Total events found: #{event_count}
          - Events processed: #{processed_count}
          - Successful venues: #{successful_venues_count}
          - Started at: #{DateTime.to_iso8601(start_time)}
          - Completed at: #{DateTime.to_iso8601(DateTime.utc_now())}
          - Scraper version: #{@version}
          """)

          {:ok, events}

        {:error, reason} ->
          Logger.error("❌ Failed to fetch events: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("❌ Scraper failed: #{Exception.message(e)}")
        Logger.error("❌ Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        reraise e, __STACKTRACE__
    end
  end

  # Helper function to extract event data from result for JSON serialization
  defp extract_event_data(result) do
    # First, unwrap any tuples to get to the actual data
    unwrapped = case result do
      {:ok, %{venue: venue, event: {:ok, %TriviaAdvisor.Events.Event{} = event}}} ->
        # Handle the case where event is wrapped in an additional {:ok, ...} tuple
        %{venue: venue, event: event}

      {:ok, %{venue: venue, event: %TriviaAdvisor.Events.Event{} = event}} ->
        # We have both venue and event
        %{venue: venue, event: event}

      {:ok, %TriviaAdvisor.Events.Event{} = event} ->
        # We have just the event in a tuple
        %{venue: nil, event: event}

      %TriviaAdvisor.Events.Event{} = event ->
        # We have just the event directly
        %{venue: nil, event: event}

      {:error, reason} ->
        # Error case
        %{error: inspect(reason)}

      other ->
        # Unknown format
        Logger.error("Unknown result format in extract_event_data: #{inspect(other)}")
        %{error: "Unknown result format: #{inspect(other)}"}
    end

    # Now extract the data from the unwrapped result
    case unwrapped do
      %{venue: venue, event: event} when not is_nil(event) ->
        # We have an event, extract its data
        venue_data = if venue do
          %{
            venue_id: venue.id,
            venue_name: venue.name
          }
        else
          %{
            venue_id: event.venue_id,
            venue_name: nil
          }
        end

        # Merge venue data with event data
        Map.merge(venue_data, %{
          event_id: event.id,
          event_name: event.name,
          day_of_week: event.day_of_week,
          start_time: Time.to_iso8601(event.start_time),
          entry_fee_cents: event.entry_fee_cents,
          description: event.description
        })

      %{error: reason} ->
        # Pass through error
        %{error: reason}

      _ ->
        # Fallback for unexpected formats
        %{error: "Could not extract event data from: #{inspect(result)}"}
    end
  end

  # Process a venue and create an event
  defp process_venue_and_event(venue_data, source) do
    try do
      # Build venue attributes map for VenueStore
      venue_attrs = %{
        name: venue_data.venue_name,
        address: venue_data.address,
        phone: nil, # SpeedQuizzing doesn't provide phone numbers
        website: venue_data.event_url,
        latitude: venue_data.lat,
        longitude: venue_data.lng,
        postcode: venue_data.postcode
      }

      Logger.info("""
      🏢 Processing venue through VenueStore:
        Name: #{venue_attrs.name}
        Address: #{venue_attrs.address}
        Website: #{venue_attrs.website}
        Coordinates: #{venue_attrs.latitude}, #{venue_attrs.longitude}
      """)

      # Process venue through VenueStore
      case VenueStore.process_venue(venue_attrs) do
        {:ok, venue} ->
          Logger.info("✅ Successfully processed venue: #{venue.name}")

          # Check if we should fetch Google Place images
          venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

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

          # Fix time format if needed - assume PM for times without AM/PM
          start_time = format_start_time(venue_data.start_time)

          # Create event data
          event_data = %{
            raw_title: "SpeedQuizzing at #{venue.name}",
            name: venue.name,
            time_text: "#{venue_data.day_of_week} #{start_time}",
            description: venue_data.description,
            fee_text: venue_data.fee,
            source_url: venue_data.event_url,
            performer_id: get_performer_id(venue_data.performer, source.id),
            hero_image_url: nil, # Speed quizzing doesn't consistently provide images
            day_of_week: day_of_week,
            start_time: start_time
          }

          # Process event through EventStore
          result = EventStore.process_event(venue, event_data, source.id)

          case result do
            {:ok, event} ->
              Logger.info("✅ Successfully created event for venue: #{venue.name}")
              # Return a consistent format with both venue and event
              {:ok, %{venue: venue, event: event}}
            {:error, reason} ->
              Logger.error("❌ Failed to create event: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("❌ Failed to process venue: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("""
        ❌ Failed to process venue and event
        Error: #{Exception.message(e)}
        Venue Data: #{inspect(venue_data)}
        """)
        {:error, e}
    end
  end

  # Get performer ID if performer data is available
  defp get_performer_id(nil, _source_id), do: nil
  defp get_performer_id(performer, source_id) when is_map(performer) do
    # Download the profile image if URL is available
    profile_image = if is_binary(performer.profile_image) and performer.profile_image != "" do
      ImageDownloader.download_performer_image(performer.profile_image)
    else
      nil
    end

    # Create performer with downloaded image
    case Performer.find_or_create(%{
      name: performer.name,
      profile_image: profile_image,
      source_id: source_id
    }) do
      {:ok, performer} -> performer.id
      _ -> nil
    end
  end

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
      fee_text: venue_data.fee,
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

  # Format time string, assuming PM for ambiguous times (no am/pm)
  defp format_start_time(time) when is_binary(time) do
    # Already parsed by time parser
    case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time(time) do
      {:ok, formatted_time} -> formatted_time
      _ ->
        # Handle "6:30" format (no am/pm) - assume PM
        case Regex.run(~r/^(\d{1,2}):(\d{2})$/, time) do
          [_, hour, minutes] ->
            hour_int = String.to_integer(hour)
            # Assume PM for hours 1-11
            hour_24 = if hour_int < 12, do: hour_int + 12, else: hour_int
            "#{String.pad_leading("#{hour_24}", 2, "0")}:#{minutes}"
          _ ->
            # Handle "6" format (just a number, no minutes or am/pm)
            case Regex.run(~r/^(\d{1,2})$/, time) do
              [_, hour] ->
                hour_int = String.to_integer(hour)
                # Assume PM for hours 1-11
                hour_24 = if hour_int < 12, do: hour_int + 12, else: hour_int
                "#{String.pad_leading("#{hour_24}", 2, "0")}:00"
              _ ->
                # Can't parse, return as is
                time
            end
        end
    end
  end
  defp format_start_time(nil), do: "20:00" # Default time
  defp format_start_time(time), do: time # Handle any other type
end

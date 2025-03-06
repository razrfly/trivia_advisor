defmodule TriviaAdvisor.Scraping.Oban.SpeedQuizzingDetailJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.VenueExtractor
  # Enable aliases for venue and event processing
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    event_id = Map.get(args, "event_id")
    source_id = Map.get(args, "source_id")
    lat = Map.get(args, "lat")
    lng = Map.get(args, "lng")

    Logger.info("🔄 Processing SpeedQuizzing event ID: #{event_id}")

    # Get the SpeedQuizzing source
    source = Repo.get!(Source, source_id)

    # Call the existing venue extractor to get venue details
    case VenueExtractor.extract(event_id) do
      {:ok, venue_data} ->
        # Add coordinates from the index data if available
        venue_data = if lat && lng do
          Map.merge(venue_data, %{lat: lat, lng: lng})
        else
          venue_data
        end

        # Log the venue details (reusing existing code pattern)
        log_venue_details(venue_data)

        # Process venue and create event using existing code patterns
        result = process_venue_and_event(venue_data, source)

        # Debug log the exact structure we're getting
        Logger.debug("📊 Result structure: #{inspect(result)}")

        # Handle the result with better pattern matching
        handle_processing_result(result)

      {:error, reason} ->
        Logger.error("❌ Failed to extract venue details for event ID #{event_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # A catch-all handler that logs the structure and converts to a standardized format
  defp handle_processing_result(result) do
    Logger.info("🔄 Processing result with structure: #{inspect(result)}")

    case result do
      # First handle the nested structures
      {:ok, {:ok, %TriviaAdvisor.Events.Event{} = event}} ->
        Logger.info("✅ Successfully processed event with ID: #{event.id}")
        {:ok, %{event_id: event.id}}

      # Handle direct event map with venue
      {:ok, %{venue: venue, event: {:ok, %TriviaAdvisor.Events.Event{} = event}}} ->
        Logger.info("✅ Successfully processed event: #{event.name} at #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      # Handle direct event map
      {:ok, %{venue: venue, event: %TriviaAdvisor.Events.Event{} = event}} ->
        Logger.info("✅ Successfully processed event: #{event.name} at #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      # Handle just event in map
      {:ok, %{event: {:ok, %TriviaAdvisor.Events.Event{} = event}}} ->
        Logger.info("✅ Successfully processed event: #{event.name}")
        {:ok, %{event_id: event.id}}

      # Handle just event in map
      {:ok, %{event: %TriviaAdvisor.Events.Event{} = event}} ->
        Logger.info("✅ Successfully processed event: #{event.name}")
        {:ok, %{event_id: event.id}}

      # Handle direct event
      {:ok, %TriviaAdvisor.Events.Event{} = event} ->
        Logger.info("✅ Successfully processed event with ID: #{event.id}")
        {:ok, %{event_id: event.id}}

      # Handle errors
      {:error, reason} ->
        Logger.error("❌ Failed to process venue and event: #{inspect(reason)}")
        {:error, reason}

      # Catch-all for unexpected formats
      other ->
        Logger.error("❌ Unexpected result format: #{inspect(other)}")
        {:error, "Unexpected result format"}
    end
  end

  # The following functions are adapted from the SpeedQuizzing scraper to avoid modifying original code

  # Process a venue and create an event - copied from SpeedQuizzing.Scraper
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
          create_event_for_venue(venue, venue_data, source)

        {:error, :missing_city} ->
          # Return the error rather than trying to create a fallback
          Logger.error("❌ Failed to process venue: missing city data")
          {:error, :missing_city}

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

  # Extract creating event to separate function
  defp create_event_for_venue(venue, venue_data, source) do
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
  end

  # Get performer ID if performer data is available
  defp get_performer_id(nil, _source_id), do: nil
  defp get_performer_id(performer, source_id) when is_map(performer) do
    # Create performer
    case Performer.find_or_create(%{
      name: performer.name,
      profile_image: nil, # Skip image download for now
      source_id: source_id
    }) do
      {:ok, performer} -> performer.id
      _ -> nil
    end
  end

  # Log venue details
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
      venue_data.start_time
    end

    # Create standardized venue data for logging
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

    # Just log the venue details instead of calling VenueHelpers
    Logger.info("""
    📋 Event Details:
      Venue: #{standardized_venue_data.title}
      Address: #{standardized_venue_data.address}
      Time: #{standardized_venue_data.time_text}
      Fee: #{standardized_venue_data.fee_text}
      Day: #{standardized_venue_data.day_of_week}
    """)
  end

  # Format time string, assuming PM for ambiguous times (no am/pm)
  defp format_start_time(time) when is_binary(time) do
    # Try to use the TimeParser if it's available
    if function_exported?(TriviaAdvisor.Scraping.Helpers.TimeParser, :parse_time, 1) do
      case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time(time) do
        {:ok, formatted_time} -> formatted_time
        _ -> manual_format_time(time)
      end
    else
      manual_format_time(time)
    end
  end
  defp format_start_time(nil), do: "20:00" # Default time
  defp format_start_time(time), do: time # Handle any other type

  # Manual time formatting backup
  defp manual_format_time(time) do
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

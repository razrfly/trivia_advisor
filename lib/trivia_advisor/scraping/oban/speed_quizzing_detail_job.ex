defmodule TriviaAdvisor.Scraping.Oban.SpeedQuizzingDetailJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.VenueExtractor
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob
  # Enable aliases for venue and event processing
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id} = _job) do
    event_id = Map.get(args, "event_id")
    source_id = Map.get(args, "source_id")
    lat = Map.get(args, "lat")
    lng = Map.get(args, "lng")
    # Get additional args that might be provided from the index job
    args_day = Map.get(args, "day_of_week")
    args_time = Map.get(args, "start_time")
    args_fee = Map.get(args, "fee")

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

        # Use values from args when the extractor provides "Unknown"
        venue_data = venue_data
        |> maybe_replace_unknown(:day_of_week, args_day)
        |> maybe_replace_unknown(:start_time, args_time)
        |> maybe_replace_unknown(:fee, args_fee)

        # Log the venue details (reusing existing code pattern)
        log_venue_details(venue_data)

        # Process venue and create event using existing code patterns
        result = process_venue_and_event(venue_data, source)

        # Debug log the exact structure we're getting
        Logger.debug("📊 Result structure: #{inspect(result)}")

        # Handle the result with better pattern matching
        processed_result = handle_processing_result(result)

        # Ensure we have the day_of_week and start_time in the metadata
        metadata = Map.new(venue_data)
        |> Map.put("day_of_week", Map.get(venue_data, :day_of_week))
        |> Map.put("start_time", Map.get(venue_data, :start_time))

        # Update job metadata with important details about what was processed
        JobMetadata.update_detail_job(job_id, metadata, result)

        processed_result

      {:error, reason} ->
        Logger.error("❌ Failed to extract venue details for event ID #{event_id}: #{inspect(reason)}")

        # Update job metadata with error information
        JobMetadata.update_error(job_id, reason, context: %{
          "event_id" => event_id,
          "source_id" => source_id
        })

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
        postcode: venue_data.postcode,
        skip_image_processing: true # Skip image processing in VenueStore, we'll handle it separately
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

          # Schedule Google Place lookup job for images
          schedule_place_lookup(venue)

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

  # Schedule a GooglePlaceLookupJob to handle Google Places API operations
  defp schedule_place_lookup(venue) do
    %{"venue_id" => venue.id}
    |> GooglePlaceLookupJob.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info("📍 Scheduled Google Place lookup for venue: #{venue.name}")
      {:error, reason} ->
        Logger.warning("⚠️ Failed to schedule Google Place lookup: #{inspect(reason)}")
    end
  end

  # Extract creating event to separate function
  defp create_event_for_venue(venue, venue_data, source) do
    # If day_of_week is "Unknown", skip this event entirely
    if venue_data.day_of_week == "Unknown" do
      Logger.info("⏩ Skipping event for venue #{venue.name} because day_of_week is Unknown")
      {:error, :invalid_day_of_week}
    else
      # Parse day of week
      day_of_week = case venue_data.day_of_week do
        "Monday" -> 1
        "Tuesday" -> 2
        "Wednesday" -> 3
        "Thursday" -> 4
        "Friday" -> 5
        "Saturday" -> 6
        "Sunday" -> 7
        # If we reach here, it's not a valid day
        _ ->
          Logger.info("⏩ Skipping event for venue #{venue.name} because day_of_week '#{venue_data.day_of_week}' is invalid")
          raise "Invalid day_of_week: #{venue_data.day_of_week}"
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
  end

  # Get performer ID if performer data is available
  defp get_performer_id(nil, _source_id), do: nil
  defp get_performer_id(performer, source_id) when is_map(performer) do
    # Download the profile image if URL is available
    profile_image = if is_binary(performer.profile_image) and performer.profile_image != "" do
      case TriviaAdvisor.Scraping.Helpers.ImageDownloader.safe_download_performer_image(performer.profile_image) do
        {:ok, upload} -> upload
        {:error, reason} ->
          Logger.warning("Failed to download performer image: #{inspect(reason)}")
          nil
      end
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

  # Log venue details
  defp log_venue_details(venue_data) do
    # Parse day of week for logging purposes only
    day_of_week = case venue_data.day_of_week do
      "Monday" -> 1
      "Tuesday" -> 2
      "Wednesday" -> 3
      "Thursday" -> 4
      "Friday" -> 5
      "Saturday" -> 6
      "Sunday" -> 7
      "Unknown" -> "Unknown"  # Keep as is for logging
      _ -> "Invalid"  # Will be caught during actual processing
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

  # Helper to replace "Unknown" values with args values
  defp maybe_replace_unknown(venue_data, _key, nil), do: venue_data
  defp maybe_replace_unknown(venue_data, key, value) do
    if Map.get(venue_data, key) == "Unknown" do
      Map.put(venue_data, key, value)
    else
      venue_data
    end
  end
end

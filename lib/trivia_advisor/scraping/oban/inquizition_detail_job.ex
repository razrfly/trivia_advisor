defmodule TriviaAdvisor.Scraping.Oban.InquizitionDetailJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Ecto.Query

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Helpers.TimeParser
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{Event, EventStore, EventSource}
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @base_url "https://inquizition.com/find-a-quiz/"
  @standard_fee_text "£2.50" # Standard fee for all Inquizition quizzes
  @standard_fee_cents 250

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Handle both formats: args with venue_data as map key or string key
    venue_data = args[:venue_data] || args["venue_data"]

    venue_name = venue_data["name"]
    Logger.info("🔄 Processing Inquizition venue: #{venue_name}")
    Logger.debug("Venue data: #{inspect(venue_data)}")

    # Get source ID (default to 3 for Inquizition if not provided)
    source_id = venue_data["source_id"] || 3

    # Make sure we have a valid source ID before proceeding
    source = case source_id do
      id when is_integer(id) ->
        Repo.get(Source, id) || get_inquizition_source()
      _ ->
        get_inquizition_source()
    end

    # Log the source for debugging
    Logger.debug("📊 Using source: #{inspect(source)}")

    # Process the venue data
    result = process_venue_and_event(venue_data, source.id)

    # Log the result structure for debugging
    Logger.debug("📊 Result structure: #{inspect(result)}")

    # Handle the processing result
    handle_processing_result(result)
  end

  # Fallback to get Inquizition source
  defp get_inquizition_source do
    # The name in the database is lowercase "inquizition"
    Repo.get_by!(Source, slug: "inquizition")
  end

  # Handle different result formats - this is a helper function to ensure consistent return formats
  defp handle_processing_result(result) do
    case result do
      {:ok, venue} when is_struct(venue, TriviaAdvisor.Locations.Venue) ->
        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, %{venue_id: venue.id}}

      {:ok, %{venue: venue, event: {:ok, event = %TriviaAdvisor.Events.Event{}}}} ->
        # Handle nested {:ok, event} tuple
        Logger.info("✅ Successfully processed venue and event: #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      {:ok, %{venue: venue, event: event = %TriviaAdvisor.Events.Event{}}} ->
        Logger.info("✅ Successfully processed venue and event: #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      {:ok, %{venue: venue, event: event = %TriviaAdvisor.Events.Event{}, status: status}} ->
        Logger.info("✅ Successfully processed venue and event (#{status}): #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event.id, status: status}}

      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        {:error, reason}

      other ->
        Logger.error("❌ Unexpected result format: #{inspect(other)}")
        {:error, "Unexpected result format"}
    end
  end

  # Process a venue and create an event from the raw data
  defp process_venue_and_event(venue_data, source_id) do
    # Special case for The White Horse which has known time data
    venue_data = if venue_data["name"] == "The White Horse" &&
                   (venue_data["time_text"] == "" || is_nil(venue_data["time_text"])) do
      Logger.info("🔍 Adding missing time data for The White Horse")
      Map.merge(venue_data, %{
        "time_text" => "Sundays, 7pm",
        "day_of_week" => 7,
        "start_time" => "19:00"  # Use 24-hour format that EventStore expects
      })
    else
      venue_data
    end

    # Get time_text - provide a default if nil
    time_text = case Map.get(venue_data, "time_text") do
      nil ->
        Logger.info("⚠️ No time_text provided for venue #{venue_data["name"]}, using default")
        "Every Thursday at 8pm"  # Default time for venues with missing time data
      "" ->
        Logger.info("⚠️ Empty time_text provided for venue #{venue_data["name"]}, using default")
        "Every Thursday at 8pm"  # Default for empty string
      value -> value
    end

    # Use explicitly provided day_of_week and start_time if available, otherwise parse from time_text
    parsed_time = cond do
      # If both day_of_week and start_time are provided, use them directly
      venue_data["day_of_week"] && venue_data["start_time"] ->
        %{
          day_of_week: venue_data["day_of_week"],
          start_time: venue_data["start_time"],
          frequency: venue_data["frequency"] || :weekly
        }

      # Otherwise parse from time_text
      true ->
        case TimeParser.parse_time_text(time_text) do
          {:ok, data} -> data
          {:error, reason} ->
            Logger.warning("⚠️ Could not parse time: #{reason}")
            %{day_of_week: nil, start_time: nil, frequency: nil}
        end
    end

    # Create venue data for VenueStore
    venue_attrs = %{
      name: venue_data["name"],
      address: venue_data["address"],
      phone: venue_data["phone"],
      website: venue_data["website"],
      facebook: venue_data["facebook"],
      instagram: venue_data["instagram"]
    }

    # Process venue through VenueStore (creates or updates the venue)
    case VenueStore.process_venue(venue_attrs) do
      {:ok, venue} ->
        Logger.info("✅ Successfully processed venue: #{venue.name}")

        # Check if we should fetch Google Place images
        venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

        # Get fee from venue_data or use standard
        fee_text = venue_data["entry_fee"] || @standard_fee_text

        # Get source_url or create default
        source_url = venue_data["source_url"] || "#{@base_url}##{venue.name}"

        # Get description or use time_text
        description = venue_data["description"] || time_text

        # Check for existing events for this venue from this source
        existing_event = find_existing_event(venue.id, source_id)

        # Different handling based on whether we found an event and what changed
        cond do
          existing_event && existing_event.day_of_week == parsed_time.day_of_week ->
            # Same day, maybe update time
            if existing_event.start_time != parsed_time.start_time do
              # Time changed - update the existing event
              Logger.info("🕒 Updating event time for #{venue.name} from #{existing_event.start_time} to #{parsed_time.start_time}")

              update_attrs = %{
                start_time: parsed_time.start_time,
                time_text: format_time_for_event_store(time_text, parsed_time.day_of_week, parsed_time.start_time),
                description: description
              }

              case update_event(existing_event, update_attrs) do
                {:ok, updated_event} ->
                  Logger.info("✅ Successfully updated event time for venue: #{venue.name}")
                  {:ok, %{venue: venue, event: updated_event, status: :updated}}
                {:error, reason} ->
                  Logger.error("❌ Failed to update event: #{inspect(reason)}")
                  {:error, reason}
              end
            else
              # No changes needed
              Logger.info("⏩ No changes needed for existing event at venue: #{venue.name}")
              {:ok, %{venue: venue, event: existing_event, status: :unchanged}}
            end

          existing_event && existing_event.day_of_week != parsed_time.day_of_week ->
            # Day changed - create a new event (keep the old one)
            Logger.info("📅 Day changed for venue #{venue.name} from #{existing_event.day_of_week} to #{parsed_time.day_of_week} - creating new event")

            # Create event data
            event_data = %{
              raw_title: "Inquizition Quiz at #{venue.name}",
              name: venue.name,
              time_text: format_time_for_event_store(time_text, parsed_time.day_of_week, parsed_time.start_time),
              description: description,
              fee_text: fee_text,
              source_url: source_url,
              hero_image_url: venue_data["hero_image_url"],
              day_of_week: parsed_time.day_of_week,
              start_time: parsed_time.start_time,
              entry_fee_cents: @standard_fee_cents
            }

            # Process new event through EventStore
            case EventStore.process_event(venue, event_data, source_id) do
              {:ok, event} ->
                Logger.info("✅ Successfully created new event for venue: #{venue.name}")
                {:ok, %{venue: venue, event: event, status: :created_new}}
              {:error, reason} ->
                Logger.error("❌ Failed to create new event: #{inspect(reason)}")
                {:error, reason}
            end

          true ->
            # No existing event or first time processing - create a new one
            # Create event data
            event_data = %{
              raw_title: "Inquizition Quiz at #{venue.name}",
              name: venue.name,
              time_text: format_time_for_event_store(time_text, parsed_time.day_of_week, parsed_time.start_time),
              description: description,
              fee_text: fee_text,
              source_url: source_url,
              hero_image_url: venue_data["hero_image_url"],
              day_of_week: parsed_time.day_of_week,
              start_time: parsed_time.start_time,
              entry_fee_cents: @standard_fee_cents
            }

            # Process event through EventStore
            case EventStore.process_event(venue, event_data, source_id) do
              {:ok, event} ->
                Logger.info("✅ Successfully created event for venue: #{venue.name}")
                {:ok, %{venue: venue, event: event, status: :created}}
              {:error, reason} ->
                Logger.error("❌ Failed to create event: #{inspect(reason)}")
                {:error, reason}
            end
        end

      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Find existing event for a venue from a specific source
  defp find_existing_event(venue_id, source_id) do
    # Query for events from this venue that are linked to this source through EventSource
    # Make sure to use a proper join to avoid the source_id field error
    Repo.one(
      from e in Event,
      join: es in EventSource, on: es.event_id == e.id,
      where: e.venue_id == ^venue_id and es.source_id == ^source_id,
      order_by: [desc: e.inserted_at],
      limit: 1,
      select: e
    )
  end

  # Update an existing event with new attributes
  defp update_event(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  # Format time_text for EventStore processing
  # Convert formats like "Sundays, 7pm" to include proper "20:00" format that EventStore expects
  defp format_time_for_event_store(time_text, day_of_week, start_time) do
    # If we already have a parsed start_time as a string in the correct format
    if is_binary(start_time) && Regex.match?(~r/^\d{2}:\d{2}$/, start_time) do
      # Just append the formatted time to the day for EventStore to parse
      day_name = case day_of_week do
        1 -> "Monday"
        2 -> "Tuesday"
        3 -> "Wednesday"
        4 -> "Thursday"
        5 -> "Friday"
        6 -> "Saturday"
        7 -> "Sunday"
        _ -> "Thursday" # Default to Thursday
      end
      "#{day_name} #{start_time}"
    else
      # Original time_text has the correct format for EventStore
      time_text
    end
  end

  # Check if we need to process this venue
  defp should_process_venue?(venue, source_id) do
    # Check if there's an existing event for this venue from this source
    existing_event = find_existing_event(venue.id, source_id)

    # If no existing event, we should process
    is_nil(existing_event)
  end
end

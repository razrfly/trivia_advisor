defmodule TriviaAdvisor.Scraping.Oban.InquizitionDetailJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Helpers.TimeParser
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @base_url "https://inquizition.com/find-a-quiz/"
  @standard_fee_text "£2.50" # Standard fee for all Inquizition quizzes
  @standard_fee_cents 250

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_data" => venue_data}}) do
    venue_name = venue_data["name"]
    Logger.info("🔄 Processing Inquizition venue: #{venue_name}")

    # Get source ID
    source_id = venue_data["source_id"]
    _source = Repo.get!(Source, source_id)

    # Process the venue data
    result = process_venue_and_event(venue_data, source_id)

    # Log the result structure for debugging
    Logger.debug("📊 Result structure: #{inspect(result)}")

    # Handle the processing result
    handle_processing_result(result)
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
    # Get time_text - provide a default if nil
    time_text = case Map.get(venue_data, "time_text") do
      nil ->
        Logger.info("⚠️ No time_text provided for venue #{venue_data["name"]}, using default")
        "Every Thursday at 8pm"  # Default time for venues with missing time data
      value -> value
    end

    # Parse time data using the helper
    parsed_time = case TimeParser.parse_time_text(time_text) do
      {:ok, data} -> data
      {:error, reason} ->
        Logger.warning("⚠️ Could not parse time: #{reason}")
        %{day_of_week: nil, start_time: nil, frequency: nil}
    end

    # Create venue data for VenueStore
    venue_attrs = %{
      name: venue_data["name"],
      address: venue_data["address"],
      phone: venue_data["phone"],
      website: venue_data["website"]
    }

    # Process venue through VenueStore (creates or updates the venue)
    case VenueStore.process_venue(venue_attrs) do
      {:ok, venue} ->
        Logger.info("✅ Successfully processed venue: #{venue.name}")

        # Check if we should fetch Google Place images
        venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

        # Create event data
        event_data = %{
          raw_title: "Inquizition Quiz at #{venue.name}",
          name: venue.name,
          time_text: time_text,
          description: time_text,
          fee_text: @standard_fee_text,
          source_url: "#{@base_url}##{venue.name}",
          hero_image_url: nil,
          day_of_week: parsed_time.day_of_week,
          start_time: parsed_time.start_time,
          entry_fee_cents: @standard_fee_cents
        }

        # Process event through EventStore
        case EventStore.process_event(venue, event_data, source_id) do
          {:ok, event} ->
            Logger.info("✅ Successfully created event for venue: #{venue.name}")
            {:ok, %{venue: venue, event: event}}
          {:error, reason} ->
            Logger.error("❌ Failed to create event: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

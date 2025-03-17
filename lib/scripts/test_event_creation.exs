require Logger

# Start required services (handle already started case)
Logger.info("Starting GooglePlacesService")
case TriviaAdvisor.Services.GooglePlacesService.start_link([]) do
  {:ok, _} -> Logger.info("GooglePlacesService started")
  {:error, {:already_started, _}} -> Logger.info("GooglePlacesService already running")
  error -> Logger.error("Failed to start GooglePlacesService: #{inspect(error)}")
end

Logger.info("Starting GooglePlaceImageStore")
case TriviaAdvisor.Services.GooglePlaceImageStore.start_link([]) do
  {:ok, _} -> Logger.info("GooglePlaceImageStore started")
  {:error, {:already_started, _}} -> Logger.info("GooglePlaceImageStore already running")
  error -> Logger.error("Failed to start GooglePlaceImageStore: #{inspect(error)}")
end

# Get the pubquiz source
source = TriviaAdvisor.Repo.get_by!(TriviaAdvisor.Scraping.Source, name: "pubquiz")
Logger.info("Using source: #{source.name} (ID: #{source.id})")

# Create a test venue
venue_attrs = %{
  name: "Test Venue #{:rand.uniform(1000)}",
  address: "Test Address, Warsaw, Poland",
  phone: "+48123456789",
  website: "https://example.com/test",
  skip_image_processing: true
}

Logger.info("Creating test venue: #{venue_attrs.name}")
{:ok, venue} = TriviaAdvisor.Locations.VenueStore.process_venue(venue_attrs)
Logger.info("Created venue with ID: #{venue.id}")

# Ensure venue is properly preloaded
venue = TriviaAdvisor.Repo.preload(venue, [city: :country])

# Create event data with explicit entry fee
entry_fee_cents = 1500
event_data = %{
  "raw_title" => "Test Quiz at #{venue.name}",
  "name" => "Test Quiz at #{venue.name}",
  "time_text" => "Tuesday 20:00",
  "description" => "A test quiz event",
  "fee_text" => "#{entry_fee_cents / 100}",
  "source_url" => "https://example.com/test",
  "hero_image_url" => "",
  "day_of_week" => 2,
  "start_time" => ~T[20:00:00],
  "frequency" => :weekly,
  "entry_fee_cents" => entry_fee_cents,
  "override_entry_fee_cents" => entry_fee_cents
}

Logger.info("Creating event with data: #{inspect(event_data)}")

# Process the event
result = TriviaAdvisor.Events.EventStore.process_event(venue, event_data, source.id)
Logger.info("Event creation result: #{inspect(result)}")

case result do
  {:ok, {:ok, event}} ->
    Logger.info("Created event with ID: #{event.id}")
    Logger.info("Event details:")
    Logger.info("  Name: #{event.name}")
    Logger.info("  Day: #{event.day_of_week}")
    Logger.info("  Time: #{event.start_time}")
    Logger.info("  Fee: #{event.entry_fee_cents} cents")

    # Verify the event in the database
    db_event = TriviaAdvisor.Events.Event |> TriviaAdvisor.Repo.get(event.id)
    Logger.info("Database event:")
    Logger.info("  Name: #{db_event.name}")
    Logger.info("  Day: #{db_event.day_of_week}")
    Logger.info("  Time: #{db_event.start_time}")
    Logger.info("  Fee: #{db_event.entry_fee_cents} cents")

  _ ->
    Logger.error("Failed to create event")
end

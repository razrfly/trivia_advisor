# Test script to verify deletion behavior between events and performers
# Make sure to run this in an IEx session with `iex -S mix`
# or from the command line with `mix run test_performer_deletion.exs`

# Load application to ensure all modules are available
Application.ensure_all_started(:trivia_advisor)

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Locations
alias TriviaAdvisor.Locations.{City, Country, Venue}
alias TriviaAdvisor.Events
alias TriviaAdvisor.Events.{Event, Performer}
alias TriviaAdvisor.Scraping
alias TriviaAdvisor.Scraping.Source
import Ecto.Query

# Helper to create test data
create_test_venue = fn ->
  # Get existing country (first one from the database)
  country = Repo.one(from c in Country, limit: 1)
  unless country do
    raise "No country found in the database. Please run seed data first."
  end

  # Get existing city (first one from the database)
  city = Repo.one(from c in City, where: c.country_id == ^country.id, limit: 1)
  unless city do
    raise "No city found in the database for country #{country.name}. Please run seed data first."
  end

  # Create venue with a unique slug
  random_suffix = :rand.uniform(1000000) |> Integer.to_string()
  {:ok, venue} = Repo.insert(%Venue{
    name: "Test Venue #{random_suffix}",
    address: "123 Test Street",
    latitude: Decimal.new("51.5074"),
    longitude: Decimal.new("-0.1278"),
    city_id: city.id,
    slug: "test-venue-#{random_suffix}"
  })

  venue
end

# Create test source
create_test_source = fn ->
  # Create source with a unique slug and URL
  random_suffix = :rand.uniform(1000000) |> Integer.to_string()
  {:ok, source} = Scraping.create_source(%{
    name: "Test Source #{random_suffix}",
    website_url: "https://example.com/test-#{random_suffix}",
    url: "https://example.com/test-#{random_suffix}",
    slug: "test-source-#{random_suffix}"
  })
  source
end

# Create a test performer
create_test_performer = fn source_id ->
  random_suffix = :rand.uniform(1000000) |> Integer.to_string()
  {:ok, performer} = Repo.insert(%Performer{
    name: "Test Performer #{random_suffix}",
    source_id: source_id
  })
  performer
end

# Create an event with performer
create_test_event = fn venue, performer_id ->
  {:ok, event} = Events.create_event(%{
    name: "Test Quiz",
    day_of_week: 2, # Tuesday
    start_time: ~T[19:00:00],
    frequency: :weekly,
    venue_id: venue.id,
    description: "Test description",
    performer_id: performer_id
  })
  event
end

# Test function to verify deletion behavior
test_performer_deletion = fn ->
  # Step 1: Create test data
  IO.puts("Creating test venue, performer, and event...")
  venue = create_test_venue.()
  source = create_test_source.()
  performer = create_test_performer.(source.id)
  event = create_test_event.(venue, performer.id)

  # Step 2: Verify creation
  IO.puts("\nVerifying created data:")
  venue_check = Repo.get(Venue, venue.id)
  IO.puts("Venue exists: #{venue_check != nil}")

  performer_check = Repo.get(Performer, performer.id)
  IO.puts("Performer exists: #{performer_check != nil}")

  event_check = Repo.get(Event, event.id)
  IO.puts("Event exists: #{event_check != nil}")

  # Step 3: Delete the event
  IO.puts("\nDeleting event...")
  Events.delete_event(event)

  # Step 4: Verify whether performer is still present
  IO.puts("\nVerifying after event deletion:")
  event_check = Repo.get(Event, event.id)
  IO.puts("Event exists: #{event_check != nil}")

  performer_check = Repo.get(Performer, performer.id)
  IO.puts("Performer exists: #{performer_check != nil}")

  if performer_check == nil do
    IO.puts("\n❌ UNEXPECTED BEHAVIOR! Performer was deleted when event was deleted.")
  else
    IO.puts("\n✅ EXPECTED BEHAVIOR! Performer was NOT deleted when event was deleted.")
    IO.puts("This confirms performers can be shared across multiple events.")
  end

  # Step 5: Now delete the venue and check if events and performers are handled correctly
  IO.puts("\nNow deleting venue to see cascading effects...")
  Locations.delete_venue(venue)

  # Step 6: Check cascading effects
  IO.puts("\nVerifying after venue deletion:")
  venue_check = Repo.get(Venue, venue.id)
  IO.puts("Venue exists: #{venue_check != nil}")

  # Event should be deleted due to cascade
  event_check = Repo.get(Event, event.id)
  IO.puts("Event exists: #{event_check != nil}")

  # Performer should still exist
  performer_check = Repo.get(Performer, performer.id)
  IO.puts("Performer exists: #{performer_check != nil}")

  if performer_check == nil do
    IO.puts("\n❌ UNEXPECTED BEHAVIOR! Performer was deleted when venue was deleted (cascading to event).")
  else
    IO.puts("\n✅ EXPECTED BEHAVIOR! Performer was NOT deleted when venue was deleted (cascading to event).")
    IO.puts("This confirms performers are independent entities that can exist without related events.")
  end

  # Clean up
  IO.puts("\nCleaning up test data...")
  Repo.delete(performer)
  Repo.delete(source)
end

# Run the test
test_performer_deletion.()

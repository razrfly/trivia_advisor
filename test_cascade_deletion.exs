# Test script to verify cascade deletion between venues and events
# Make sure to run this in an IEx session with `iex -S mix`
# or from the command line with `mix run test_cascade_deletion.exs`

# Load application to ensure all modules are available
Application.ensure_all_started(:trivia_advisor)

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Locations
alias TriviaAdvisor.Locations.{City, Country, Venue}
alias TriviaAdvisor.Events
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Scraping
alias TriviaAdvisor.Utils.Slug

# Helper to create test data
create_test_venue = fn ->
  # Create country
  {:ok, country} = Repo.insert(%Country{
    code: "XX",
    name: "Test Country",
    slug: "test-country"
  })

  # Create city
  {:ok, city} = Repo.insert(%City{
    name: "Test City",
    country_id: country.id,
    slug: "test-city"
  })

  # Create venue
  {:ok, venue} = Repo.insert(%Venue{
    name: "Test Venue",
    address: "123 Test Street",
    latitude: Decimal.new("51.5074"),
    longitude: Decimal.new("-0.1278"),
    city_id: city.id,
    slug: "test-venue"
  })

  venue
end

# Create test source
create_test_source = fn ->
  {:ok, source} = Scraping.create_source(%{
    name: "Test Source",
    website_url: "https://example.com/test",
    url: "https://example.com/test",
    slug: "test-source"
  })
  source
end

# Create an event for a venue
create_test_event = fn venue, source_id ->
  {:ok, event} = Events.create_event(%{
    name: "Test Quiz",
    day_of_week: 2, # Tuesday
    start_time: ~T[19:00:00],
    frequency: :weekly,
    venue_id: venue.id,
    description: "Test description",
    source_id: source_id
  })
  event
end

# Test function to verify deletion cascade
test_cascade_deletion = fn ->
  # Step 1: Create test data
  IO.puts("Creating test venue and events...")
  venue = create_test_venue.()
  source = create_test_source.()
  event = create_test_event.(venue, source.id)

  # Step 2: Verify creation
  IO.puts("\nVerifying created data:")
  venue_check = Repo.get(Venue, venue.id)
  IO.puts("Venue exists: #{venue_check != nil}")

  event_check = Repo.get(Event, event.id)
  IO.puts("Event exists: #{event_check != nil}")

  # Step 3: Delete the venue
  IO.puts("\nDeleting venue...")
  Locations.delete_venue(venue)

  # Step 4: Verify cascade deletion
  IO.puts("\nVerifying deletion cascade:")
  venue_check = Repo.get(Venue, venue.id)
  IO.puts("Venue exists: #{venue_check != nil}")

  event_check = Repo.get(Event, event.id)
  IO.puts("Event exists: #{event_check != nil}")

  if event_check != nil do
    IO.puts("\n❌ CASCADE DELETION FAILED! Events were not automatically deleted when venue was deleted.")
    IO.puts("Check your database foreign key constraints.")
  else
    IO.puts("\n✅ CASCADE DELETION WORKING! Events were automatically deleted when venue was deleted.")
  end
end

# Run the test
test_cascade_deletion.()

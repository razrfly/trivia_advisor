# Script to test if last_seen_at is being updated properly

# Import dependencies with a proper Elixir application
Mix.start()
Application.ensure_all_started(:trivia_advisor)

require Logger
import Ecto.Query, warn: false
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.{EventSource, Event, EventStore}
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Helpers.TimeParser

Logger.info("🧪 Starting EventStore.process_event timestamp test")

# 1. Get the Quizmeisters source
quizmeisters_source = Repo.get_by!(Source, website_url: "https://quizmeisters.com")
Logger.info("📊 Found source: #{quizmeisters_source.name} (ID: #{quizmeisters_source.id})")

# 2. Get or create a test venue
venue_name = "Test Venue for Timestamp Test"
venue = case Repo.get_by(Venue, name: venue_name) do
  nil ->
    Logger.info("🏢 Creating test venue: #{venue_name}")
    # Use city_id 269 which we found from our query
    {:ok, venue} = Repo.insert(%Venue{
      name: venue_name,
      slug: "test-venue-for-timestamp-test",
      address: "123 Test Street",
      latitude: 0,
      longitude: 0,
      city_id: 269
    })
    venue
  existing_venue ->
    Logger.info("🏢 Using existing test venue: #{existing_venue.name} (ID: #{existing_venue.id})")
    existing_venue
end

# 3. Check if we have any existing event_source for this source and venue
query = from es in EventSource,
  join: e in assoc(es, :event),
  where: es.source_id == ^quizmeisters_source.id and e.venue_id == ^venue.id,
  order_by: [desc: es.last_seen_at],
  limit: 1

existing_event_source = Repo.one(query)

if existing_event_source do
  Logger.info("🕒 Current last_seen_at for event_source #{existing_event_source.id}: #{inspect(existing_event_source.last_seen_at)}")
else
  Logger.info("ℹ️ No existing event_source found for this test venue")
end

# 4. Record timestamp before running the operation
before_timestamp = DateTime.utc_now()
Process.sleep(1000) # Sleep 1 second to ensure timestamps will be different
Logger.info("⏱️ Timestamp before running operation: #{DateTime.to_string(before_timestamp)}")

# 5. Prepare event data with a properly formatted time
# EventStore.parse_time expects a time string with format like "Monday 19:00"
day_of_week = 1 # Monday
time_string = "19:00" # 7:00 PM in 24-hour format
time_text = "Monday #{time_string}"

event_data = %{
  "raw_title" => "Test Trivia Night",
  "name" => venue.name,
  "time_text" => time_text,
  "day_of_week" => day_of_week,
  "start_time" => time_string,
  "description" => "Test description for trivia night",
  "fee_text" => "Free",
  "hero_image_url" => nil,
  "source_url" => "https://quizmeisters.com/test-venue-source-url",
  "performer_id" => nil
}

Logger.info("🏃‍♂️ Calling EventStore.process_event directly...")
result = EventStore.process_event(venue, event_data, quizmeisters_source.id)
Logger.info("✅ EventStore.process_event result: #{inspect(result)}")

# 6. Check if last_seen_at was updated
after_query = from es in EventSource,
  join: e in assoc(es, :event),
  where: es.source_id == ^quizmeisters_source.id and e.venue_id == ^venue.id,
  order_by: [desc: es.last_seen_at],
  limit: 1

case Repo.one(after_query) do
  nil ->
    Logger.error("❌ TEST FAILED: No event_source found after operation")

  event_source ->
    Logger.info("🕒 New last_seen_at for event_source #{event_source.id}: #{inspect(event_source.last_seen_at)}")

    # Check if the timestamp was updated
    if event_source.last_seen_at && DateTime.compare(event_source.last_seen_at, before_timestamp) == :gt do
      Logger.info("✅ TEST PASSED: last_seen_at was updated after EventStore.process_event")
    else
      Logger.error("❌ TEST FAILED: last_seen_at was not updated or is older than before running the operation")

      # Additional debug information
      Logger.error("🔍 Before timestamp: #{DateTime.to_string(before_timestamp)}")
      Logger.error("🔍 Event source timestamp: #{DateTime.to_string(event_source.last_seen_at)}")
      Logger.error("🔍 Comparison result: #{DateTime.compare(event_source.last_seen_at, before_timestamp)}")
    end
end

Logger.info("�� Test completed")

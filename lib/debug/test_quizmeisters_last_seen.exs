# Script to test if last_seen_at is being updated properly by QuizmeistersDetailJob

# Import dependencies with a proper Elixir application
Mix.start()
Application.ensure_all_started(:trivia_advisor)
Application.ensure_all_started(:ecto)

require Logger
import Ecto.Query
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.{EventSource, Event, EventStore}
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

Logger.info("Starting timestamp test for QuizmeistersDetailJob")

# 1. Get the Quizmeisters source
quizmeisters_source = Repo.get_by!(Source, website_url: "https://quizmeisters.com")
Logger.info("Found source: #{quizmeisters_source.name} (ID: #{quizmeisters_source.id})")

# 2. Get a real venue
venue_name = "Grill'd Carindale"
venue = case Repo.get_by(Venue, name: venue_name) do
  nil ->
    Logger.error("Test venue '#{venue_name}' not found! Using first available venue.")
    Repo.one(from v in Venue, limit: 1)
  existing_venue ->
    Logger.info("Using test venue: #{existing_venue.name} (ID: #{existing_venue.id})")
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
  Logger.info("Current last_seen_at for event_source #{existing_event_source.id}: #{inspect(existing_event_source.last_seen_at)}")
  Logger.info("Current source_url for event_source #{existing_event_source.id}: #{existing_event_source.source_url}")
else
  Logger.info("No existing event_source found for this test venue")
end

# 4. Record timestamp before running the operation
before_timestamp = DateTime.utc_now()
Process.sleep(1000) # Sleep 1 second to ensure timestamps will be different
Logger.info("Timestamp before running operation: #{DateTime.to_string(before_timestamp)}")

# 5. Create fake venue data for QuizmeistersDetailJob
source_url = "https://quizmeisters.com/venues/qld-grilld-carindale"
Logger.info("Using source_url: #{source_url}")

fake_venue_data = %{
  "name" => venue.name,
  "address" => venue.address,
  "url" => source_url, # Make sure this matches the source_url in the existing event_source
  "custom_fields" => %{
    "trivia_night" => "Thursday 7:00 PM"
  },
  "phone" => "07 3398 2565",
  "lat" => venue.latitude,
  "lng" => venue.longitude,
  "postcode" => "4152"
}

# 6. Run the job synchronously
Logger.info("Running QuizmeistersDetailJob with fake venue data")
result = QuizmeistersDetailJob.perform(%Oban.Job{
  id: -1, # Fake job ID
  args: %{
    "venue" => fake_venue_data,
    "source_id" => quizmeisters_source.id
  }
})

Logger.info("Job result: #{inspect(result)}")

# 7. Check if last_seen_at was updated
Process.sleep(1000) # Give some time for DB operations to complete
after_query = from es in EventSource,
  join: e in assoc(es, :event),
  where: es.source_id == ^quizmeisters_source.id and e.venue_id == ^venue.id,
  order_by: [desc: es.last_seen_at],
  limit: 1

case Repo.one(after_query) do
  nil ->
    Logger.error("TEST FAILED: No event_source found after operation")

  event_source ->
    Logger.info("New last_seen_at for event_source #{event_source.id}: #{inspect(event_source.last_seen_at)}")
    Logger.info("New source_url for event_source #{event_source.id}: #{event_source.source_url}")

    # Check if the timestamp was updated
    if event_source.last_seen_at && DateTime.compare(event_source.last_seen_at, before_timestamp) == :gt do
      Logger.info("TEST PASSED: last_seen_at was updated after QuizmeistersDetailJob")
    else
      Logger.error("TEST FAILED: last_seen_at was not updated or is older than before running the operation")

      # Additional debug information
      Logger.error("Before timestamp: #{DateTime.to_string(before_timestamp)}")
      Logger.error("Event source timestamp: #{DateTime.to_string(event_source.last_seen_at)}")
      Logger.error("Comparison result: #{DateTime.compare(event_source.last_seen_at, before_timestamp)}")
    end
end

Logger.info("Test completed")

# Script to test the normal InquizitionIndexJob workflow (without force_update)
require Logger
Logger.configure(level: :info)
IO.puts("Starting test for normal InquizitionIndexJob workflow (no force_update)")

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.EventSource
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
alias TriviaAdvisor.Scraping.RateLimiter
import Ecto.Query

# Function to check event source timestamps for a venue
check_event_source_timestamps = fn venue_id, source_id ->
  # Find all events for this venue
  events = Repo.all(from e in Event, where: e.venue_id == ^venue_id, select: e)

  # Get all event IDs
  event_ids = Enum.map(events, & &1.id)

  # Find event sources that link these events to our source
  event_sources = Repo.all(
    from es in EventSource,
    where: es.event_id in ^event_ids and es.source_id == ^source_id,
    select: es
  )

  Enum.each(event_sources, fn es ->
    event = Repo.get(Event, es.event_id)
    IO.puts("Event ID: #{es.event_id} (day #{event.day_of_week})")
    IO.puts("  last_seen_at: #{DateTime.to_string(es.last_seen_at)}")

    # Calculate days since update
    days_since = DateTime.diff(DateTime.utc_now(), es.last_seen_at, :day)
    IO.puts("  days since update: #{days_since}")

    # Compare with RateLimiter threshold
    skip_threshold = RateLimiter.skip_if_updated_within_days()
    IO.puts("  skip_threshold: #{skip_threshold} days")
    IO.puts("  would be skipped: #{days_since < skip_threshold}")
  end)

  {events, event_sources}
end

# First get the venue we want to test
venue_id = 123  # Andrea Ludgate Hill venue ID
source_id = 3   # Inquizition source ID

# Check timestamps before update
IO.puts("\n--- BEFORE PROCESSING ---")
{_events, event_sources_before} = check_event_source_timestamps.(venue_id, source_id)

# Now run the index job WITHOUT force_update to see what happens
IO.puts("\nRunning InquizitionIndexJob with limit=1 (NO force_update)...")
{:ok, job} = Oban.insert(InquizitionIndexJob.new(%{"limit" => 1}))

IO.puts("\nJob inserted with ID: #{job.id}")
IO.puts("Waiting for index job to complete...")

# Wait for the job to complete - longer wait for index job
:timer.sleep(10000)

# Check timestamps after update
IO.puts("\n--- AFTER PROCESSING ---")
{_events, event_sources_after} = check_event_source_timestamps.(venue_id, source_id)

# Check if any timestamps were updated
any_updated = Enum.any?(event_sources_after, fn es_after ->
  # Find the corresponding event source from before
  es_before = Enum.find(event_sources_before, fn es -> es.id == es_after.id end)

  # If it's a new event source (not in before list), it's definitely updated
  if es_before == nil do
    true
  else
    # Check if timestamp was updated
    DateTime.compare(es_after.last_seen_at, es_before.last_seen_at) == :gt
  end
end)

if any_updated do
  IO.puts("\n❓ UNEXPECTED: Timestamps were updated even though the venue was recently seen")
  IO.puts("This suggests RateLimiter.skip_if_updated_within_days() is not being applied correctly")
else
  IO.puts("\n✅ EXPECTED BEHAVIOR: No timestamps were updated")
  IO.puts("Venues updated less than #{RateLimiter.skip_if_updated_within_days()} days ago are being skipped")
  IO.puts("\nTo make this work better, we need to review how 'recently updated' is defined")
  IO.puts("Consider increasing the update frequency or modifying how skipped venues are determined")
end

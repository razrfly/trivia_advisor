# Script to test the InquizitionIndexJob with limited venues
require Logger
Logger.configure(level: :info)
IO.puts("Starting test for InquizitionIndexJob timestamp updates")

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.EventSource
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
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
    IO.puts("  days since update: #{DateTime.diff(DateTime.utc_now(), es.last_seen_at, :day)}")
  end)

  {events, event_sources}
end

# First get the venue we want to test
venue_id = 123  # Andrea Ludgate Hill venue ID
source_id = 3   # Inquizition source ID

# Check timestamps before update
IO.puts("\n--- BEFORE PROCESSING ---")
{events, event_sources_before} = check_event_source_timestamps.(venue_id, source_id)

# Now run the index job with force_update to ensure it processes our venue
IO.puts("\nRunning InquizitionIndexJob with limit=1 and force_update=true...")
{:ok, job} = Oban.insert(InquizitionIndexJob.new(%{"limit" => 1, "force_update" => true}))

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
  IO.puts("\n✅ SUCCESS: Some event source timestamps were updated")
  IO.puts("The update_all_event_sources_for_venue function is working!")
  System.stop(0)
else
  IO.puts("\n❌ FAILURE: No event source timestamps were updated")
  IO.puts("The problem is in how the IndexJob triggers the DetailJob")
  System.stop(1)
end

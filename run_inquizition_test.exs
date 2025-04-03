# Script to test the InquizitionDetailJob with Andrea Ludgate Hill
require Logger
Logger.configure(level: :info)
IO.puts("Starting test for timestamp issue with Andrea Ludgate Hill event")

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.EventSource
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob
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

# Get the existing event data to make sure our test is relevant
existing_event = Enum.find(events, fn e -> e.id == 124 end)

# Create test venue data - use the same data but with a different day_of_week to force a new event
venue_data = %{
  "name" => "Andrea Ludgate Hill",
  "address" => "47 Ludgate Hill, London, EC4M 7JZ",
  "day_of_week" => existing_event.day_of_week + 1,  # Use next day to force new event
  "description" => nil,
  "entry_fee" => "2.50",
  "facebook" => nil,
  "frequency" => "weekly",
  "hero_image" => nil,
  "hero_image_url" => nil,
  "instagram" => nil,
  "phone" => "020 7236 1942",
  "source_id" => 3,
  "source_url" => "https://inquizition.com/find-a-quiz/#andrea-ludgate-hill",
  "start_time" => "18:30",
  "time_text" => "Test day, 6.30pm",
  "website" => "https://andreabars.com/"
}

# Process the venue with our job
venue_job_args = %{venue_data: venue_data}
{:ok, job} = Oban.insert(InquizitionDetailJob.new(venue_job_args))

IO.puts("\nJob inserted with ID: #{job.id}")
IO.puts("Waiting for job to complete...")

# Wait for the job to complete
:timer.sleep(5000)

# Check timestamps after update
IO.puts("\n--- AFTER PROCESSING ---")
{_events, event_sources_after} = check_event_source_timestamps.(venue_id, source_id)

# Check if all timestamps were updated
all_updated = Enum.all?(event_sources_after, fn es_after ->
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

if all_updated do
  IO.puts("\n✅ SUCCESS: All event source timestamps were updated")
  System.stop(0)
else
  IO.puts("\n❌ FAILURE: Some event source timestamps were not updated")
  System.stop(1)
end

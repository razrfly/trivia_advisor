# Script to test a fix for InquizitionIndexJob timestamp issues
require Logger
Logger.configure(level: :info)
IO.puts("Starting test for InquizitionIndexJob timestamp fix")

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.EventSource
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob
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

# Get venue and source info
venue_id = 123  # Andrea Ludgate Hill venue ID
source_id = 3   # Inquizition source ID

# First, get venue info for direct access
venue = Repo.get(Venue, venue_id)
IO.puts("\nTesting with venue: #{venue.name} (ID: #{venue.id})")
source = Repo.get(Source, source_id)
IO.puts("Source: #{source.name} (ID: #{source.id})")

# Check timestamps before update
IO.puts("\n--- BEFORE MODIFICATION ---")
{_events, event_sources_before} = check_event_source_timestamps.(venue_id, source_id)

# Fix: Make the timestamps older than the skip threshold to force processing
IO.puts("\nModifying timestamps to make them older than the skip threshold...")

# Calculate a date older than the skip threshold (5 days + 1 extra day for safety)
skip_days = RateLimiter.skip_if_updated_within_days() + 1
old_timestamp = DateTime.utc_now() |> DateTime.add(-skip_days * 24 * 3600, :second)

# Update all event sources for this venue
# First get the event IDs for this venue
events_query = from e in Event, where: e.venue_id == ^venue_id, select: e.id

# Now update the event sources using the subquery
query = from es in EventSource,
  where: es.event_id in subquery(events_query) and es.source_id == ^source_id

{updated_count, _} = Repo.update_all(query, [set: [last_seen_at: old_timestamp]])
IO.puts("Modified #{updated_count} event sources")

# Check timestamps after modification
IO.puts("\n--- AFTER MODIFICATION ---")
{_events, _} = check_event_source_timestamps.(venue_id, source_id)

# APPROACH 1: Run index job with limit=1
IO.puts("\nMethod 1: Running InquizitionIndexJob with limit=1...")
{:ok, job} = Oban.insert(InquizitionIndexJob.new(%{"limit" => 1}))
IO.puts("Job inserted with ID: #{job.id}")

# Wait for job to complete
IO.puts("Waiting for index job to complete...")
:timer.sleep(10000)

# Check timestamps to see if they were updated
IO.puts("\n--- AFTER INDEX JOB ---")
{_events, event_sources_after_index} = check_event_source_timestamps.(venue_id, source_id)

# APPROACH 2: Try direct detail job for this venue
IO.puts("\nMethod 2: Running InquizitionDetailJob directly for venue #{venue.name}...")

# Create venue_data similar to what the index job would create
venue_data = %{
  "name" => venue.name,
  "address" => venue.address,
  "phone" => venue.phone,
  "website" => venue.website,
  "source_id" => source_id,
  "time_text" => "Tuesdays, 7pm",  # Sample time text
  "day_of_week" => 2,  # Tuesday
  "start_time" => "19:00"
}

# Insert the detail job directly
{:ok, detail_job} = Oban.insert(InquizitionDetailJob.new(%{venue_data: venue_data, force_update: true}))
IO.puts("Detail job inserted with ID: #{detail_job.id}")

# Wait for detail job to complete
IO.puts("Waiting for detail job to complete...")
:timer.sleep(10000)

# Check timestamps after detail job
IO.puts("\n--- AFTER DETAIL JOB ---")
{_events, event_sources_after_detail} = check_event_source_timestamps.(venue_id, source_id)

# Check if any timestamps were updated by either approach
any_updated_index = Enum.any?(event_sources_after_index, fn es_after ->
  # Find the corresponding event source from before
  es_before = Enum.find(event_sources_before, fn es -> es.id == es_after.id end)

  # If it's a new event source or timestamp was updated from the old value
  if is_nil(es_before) do
    true
  else
    DateTime.compare(es_after.last_seen_at, old_timestamp) == :gt
  end
end)

any_updated_detail = Enum.any?(event_sources_after_detail, fn es_after ->
  # Find the corresponding event source from before index job
  es_before = Enum.find(event_sources_after_index, fn es -> es.id == es_after.id end)

  # If it's a new event source or timestamp was updated
  if is_nil(es_before) do
    true
  else
    DateTime.compare(es_after.last_seen_at, es_before.last_seen_at) == :gt
  end
end)

IO.puts("\n=== RESULTS ===")
IO.puts("Index job updated timestamps: #{any_updated_index}")
IO.puts("Detail job updated timestamps: #{any_updated_detail}")

if any_updated_index or any_updated_detail do
  IO.puts("\n✅ SUCCESS: At least one approach successfully updated timestamps")
  IO.puts("\nRecommendations:")
  IO.puts("1. Use a direct detail job to process specific venues that need updating")
  IO.puts("2. OR run the index job with force_update=true")
  IO.puts("3. OR run this fix script periodically to reset timestamps")
  System.stop(0)
else
  IO.puts("\n❌ FAILURE: Neither approach updated the timestamps")
  IO.puts("This suggests there may be an issue with how the Inquizition jobs process venue data")
  System.stop(1)
end

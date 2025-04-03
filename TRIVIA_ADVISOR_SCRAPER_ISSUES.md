# Trivia Advisor Scraper Issues Analysis

## Summary of Issues

We're facing two main issues with the event scraping system:

1. **Timestamp Update Issue**: When creating new events, the system is not properly updating `last_seen_at` timestamps for existing event sources at the venue. This affects venues like "The One Tun" where a day-of-week change should trigger timestamp updates for all existing event sources from that venue.

2. **Event Detection Issue**: The system isn't properly detecting or processing events, leading to missed updates.

eg "{:ok, job} = Oban.insert(TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob.new(%{"limit" => 5}))" even with no updates to any venues in 20+ days

output "%{
  "applied_limit" => 5,
  "completed_at" => "2025-04-03T09:13:43.133326Z",
  "enqueued_jobs" => 0,
  "limited_to" => 5,
  "processed_at" => "2025-04-03T09:13:43.135341Z",
  "skipped_venues" => 5,
  "source_id" => 4,
  "total_venues" => 221
}"

## Detailed Analysis of Timestamp Update Issue

### Current Behavior

When a day of week changes for an event at a venue (e.g., moving from Thursday to Sunday):
- The system correctly creates a new event for the new day
- However, it **fails to update** the `last_seen_at` timestamp for the old event's `event_source` record
- This causes the older event sources to appear "stale" and might trigger unnecessary re-processing

### How Other Scrapers Handle This

**QuestionOneDetailJob**:
- Uses a `Task.async` to process events with explicitly captured parameters
- Updates `last_seen_at` timestamps through `EventStore.process_event` call
- Uses clear success/failure handling with consistent return structures

**QuizmeistersDetailJob** (not shown in excerpts but referenced in tests):
- Handles image refreshing correctly with explicit `force_refresh_images` flag propagation
- Careful parameter passing through process dictionary

**InquizitionDetailJob** (our problematic one):
- Has inconsistent return format handling between different code paths
- Uses a specialized `ensure_event_source_updated` function, but only for the "unchanged" path
- Lacks timestamp updates when creating new events due to day change

## Root Causes

1. **Missing Function Call**: The `update_all_event_sources_for_venue` function we added is not being called in all relevant code paths, particularly when creating new events due to day changes.

2. **Inconsistent Return Formats**: Different code paths return different data structures, causing mismatches in pattern matching later.

3. **Process Dictionary Inconsistency**: The `force_refresh_images` flag isn't properly propagated through the job execution chain.

## Audit of Other Scraper Implementations

### QuestionOneDetailJob (Best Practice Example)

1. **Clear Parameter Passing**:
   ```elixir
   # Extracts and explicitly sets force_refresh_images
   force_refresh_images = Map.get(args, "force_refresh_images", false)
   Process.put(:force_refresh_images, force_refresh_images)
   ```

2. **Consistent Event Processing**:
   ```elixir
   # Creates a task that explicitly captures the parameter
   event_task = Task.async(fn ->
     EventStore.process_event(venue, event_data, source.id, force_refresh_images: force_refresh_images)
   end)
   ```

3. **Proper Return Value Handling**:
   ```elixir
   # Returns consistent data structure regardless of success path
   {:ok, %{venue_id: venue.id, event_id: event.id}}
   ```

### ImageDownloader (Shared Component)

1. **Explicit Parameter Handling**:
   ```elixir
   # Handle nil case explicitly
   force_refresh = if is_nil(force_refresh), do: false, else: force_refresh
   ```

2. **Clear Logging**:
   ```elixir
   Logger.info("📥 Downloading image from URL: #{url}, force_refresh: #{inspect(force_refresh)}")
   ```

### Issues in InquizitionDetailJob

1. **Inconsistent Return Values**: Different code paths return different structures:
   ```elixir
   # One path returns:
   {:ok, %{venue: venue, event: event, status: :created}}
   
   # Another path returns:
   {:ok, %{venue_id: venue.id, event_id: event.id}}
   ```

2. **Missing Timestamp Updates**: When creating a new event due to day change, we don't update other event sources.

3. **Overly Complex Structure**: The function has too many branches and return formats.

## Required Fixes

1. **Add `update_all_event_sources_for_venue` Call**:
   - Must be added to the "day changed" code path when creating a new event
   - Must be added to the standard event creation path

2. **Standardize Return Formats**:
   - Ensure all code paths return consistent data structures
   - Update pattern matching in handler functions

3. **Fix Time Text Processing**:
   - Ensure proper time text formatting across all paths

4. **Improve Logging**:
   - Add clear logging for timestamp updates

## Implementation Strategy

1. **Update Return Format**: Standardize on one format for all paths:
   ```elixir
   {:ok, %{venue: venue, event: event, status: :status_type}}
   ```

2. **Add Missing Function Call**:
   - After successful event creation in both "day changed" and "no existing event" paths, add:
   ```elixir
   update_all_event_sources_for_venue(venue.id, source_id)
   ```

3. **Fix Pattern Matching**:
   - Ensure `handle_processing_result` can handle all return formats

4. **Add Test Case**:
   - Create a specific test for the "day changed" scenario to ensure timestamp updates work

## Implementation of `update_all_event_sources_for_venue` Function

Based on our audit of the codebase, we should implement the `update_all_event_sources_for_venue` function in `inquizition_detail_job.ex` as follows:

```elixir
# Update all event sources for a venue when a new event is created
# This ensures that all event sources for a venue are marked as recently updated
# even when the event itself is different (e.g., day change)
defp update_all_event_sources_for_venue(venue_id, source_id) do
  now = DateTime.utc_now()
  Logger.info("🔄 Updating timestamps for all event sources for venue: #{venue_id}")
  
  # Find all events for this venue
  events = Repo.all(from e in Event, where: e.venue_id == ^venue_id, select: e)
  
  # Get all event IDs
  event_ids = Enum.map(events, & &1.id)
  
  # Find all event sources that link these events to our source
  query = from es in EventSource,
    where: es.event_id in ^event_ids and es.source_id == ^source_id
    
  # Update all matching event sources
  {updated_count, _} = Repo.update_all(
    query,
    [set: [last_seen_at: now, updated_at: now]]
  )
  
  Logger.info("✅ Updated #{updated_count} event sources for venue: #{venue_id}")
  {:ok, updated_count}
end
```

This function should be called in two key places:

1. After successfully creating a new event due to day change:
```elixir
case EventStore.process_event(venue, event_data, source_id) do
  {:ok, event} ->
    Logger.info("✅ Successfully created new event for venue: #{venue.name}")
    # Update all existing event sources for this venue
    update_all_event_sources_for_venue(venue.id, source_id)
    {:ok, %{venue: venue, event: event, status: :created_new}}
  {:error, reason} ->
    # Error handling...
end
```

2. After successfully creating a new event when no previous event exists:
```elixir
case EventStore.process_event(venue, event_data, source_id) do
  {:ok, event} ->
    Logger.info("✅ Successfully created event for venue: #{venue.name}")
    # Update all existing event sources for this venue
    update_all_event_sources_for_venue(venue.id, source_id)
    {:ok, %{venue: venue, event: event, status: :created}}
  {:error, reason} ->
    # Error handling...
end
```

## Future Improvement Suggestions

1. **Refactor Event Processing**:
   - Reduce complexity in `process_venue_and_event` by splitting into smaller functions
   - Standardize parameter passing using explicit arguments instead of Process dictionary

2. **Enhanced Monitoring**:
   - Add more detailed logging for timestamp updates
   - Consider adding metrics for event source updates

3. **Test Coverage**:
   - Add tests specifically for timestamp updates
   - Test day change scenarios explicitly 
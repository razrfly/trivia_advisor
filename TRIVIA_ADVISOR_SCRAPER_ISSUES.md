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

### Audit Findings

After auditing `QuestionOne`, `Quizmeisters`, and `Inquizition` scrapers, I've found the following key differences:

1. **Working Scrapers (QuestionOne & Quizmeisters)**:
   - Maintain consistent event source timestamp updates through `EventStore.process_event`
   - Use clear parameter passing with explicit capture in async tasks
   - Handle all code paths with consistent return formats

2. **Problematic Scraper (Inquizition)**:
   - **Missing Function Calls**: No timestamp updates when creating new events due to day changes
   - **Inconsistent Return Formats**: Different code paths return different data structures
   - **Incomplete Event Source Management**: Only updates timestamps in the "unchanged" path

### Root Cause

The primary issue is that the `Inquizition` scraper lacks a mechanism to update all event sources for a venue when creating new events. When a day changes for an event:

1. A new event is created correctly
2. But the system fails to update timestamps for existing event sources from the same venue
3. This leads to these event sources appearing "stale" and might trigger unnecessary re-processing

## Implemented Solution

1. **Added a New Function**: `update_all_event_sources_for_venue(venue_id, source_id)`
   - Finds all events for a venue
   - Updates timestamps for all event sources linked to those events
   - Provides detailed logging for debugging

2. **Added Function Calls in Key Places**:
   - After creating a new event due to day change
   - After creating a new event when no previous event exists

The function implementation is as follows:

```elixir
defp update_all_event_sources_for_venue(venue_id, source_id) do
  now = DateTime.utc_now()
  Logger.info("🔄 Updating timestamps for all event sources for venue_id: #{venue_id}, source_id: #{source_id}")
  
  # Find all events for this venue
  query_events = from e in TriviaAdvisor.Events.Event, 
    where: e.venue_id == ^venue_id, 
    select: e.id
  
  event_ids = Repo.all(query_events)
  
  # Find and update all event sources
  query = from es in TriviaAdvisor.Events.EventSource,
    where: es.event_id in ^event_ids and es.source_id == ^source_id
    
  {updated_count, _} = Repo.update_all(
    query,
    [set: [last_seen_at: now, updated_at: now]]
  )
  
  Logger.info("✅ Updated #{updated_count} event sources for venue_id: #{venue_id}")
  {:ok, updated_count}
end
```

## Verification of the Solution

We implemented a test module `TriviaAdvisor.Scraping.TimestampTest` to verify the fix. 
Using "The One Tun" venue as a test case, we confirmed:

1. **BEFORE**: The venue had 2 existing event sources (days 1 and 2) with timestamps at "2025-04-03 09:48:24Z"

2. **Test Process**: Creating a new event on day 4 (Thursday)

3. **AFTER**: All 3 event sources (including the existing ones) had their timestamps updated to "2025-04-03 09:48:39Z"

This verifies that our fix for updating the timestamps of ALL event sources for a venue works correctly.

## Testing the Solution

To validate the fix, perform the following test:

```elixir
# Run the test with "The One Tun" venue and source_id 3 (Inquizition)
TriviaAdvisor.Scraping.TimestampTest.run_timestamp_test("The One Tun", 3)
```

Or use the provided script:
```bash
mix run run_timestamp_test.exs
```

## Future Improvement Suggestions

1. **Standardize Return Formats**:
   - Ensure all scrapers use a consistent return structure
   - This will simplify error handling and debugging

2. **Implement Unit Tests**:
   - Add automated tests that verify timestamp updates
   - Test day-change scenarios explicitly

3. **Refactor Event Processing**:
   - Consider moving the common functionality to shared modules
   - Reduce code duplication between scrapers

4. **Improve Logging**:
   - Add more structured logging for timestamp updates
   - Include before/after timestamps to aid debugging 
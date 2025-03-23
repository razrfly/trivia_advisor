# Timestamp Update Fix

This document summarizes the changes made to fix the issue with the `last_seen_at` timestamp not updating correctly for Quizmeisters venues.

## Problem

The `last_seen_at` timestamp for venues in the `event_sources` table was not being updated consistently when the Quizmeisters scraper ran. This was causing venues to appear as not having been updated recently, even though the scraper was running successfully.

## Root Cause

1. The `EventStore.process_event` function in `lib/trivia_advisor/events/event_store.ex` was only updating the timestamp when an event had actual changes.
2. The `QuizmeistersDetailJob` was calling `EventStore.process_event` incorrectly, with inconsistent URL references.

## Solutions Implemented

### 1. Modified the `upsert_event_source` Function in `event_store.ex`

Updated the function to always set the `last_seen_at` timestamp to the current time, regardless of whether any other data has changed:

```elixir
defp upsert_event_source(event_id, source_id, source_url, data) do
  now = DateTime.utc_now()

  # Build metadata from event data
  metadata = %{
    # ... metadata fields ...
  }

  # ALWAYS update the last_seen_at timestamp to now
  case Repo.get_by(EventSource, event_id: event_id, source_id: source_id) do
    nil ->
      %EventSource{}
      |> EventSource.changeset(%{
        event_id: event_id,
        source_id: source_id,
        source_url: source_url,
        metadata: metadata,
        last_seen_at: now  # Always set to current time
      })
      |> Repo.insert()

    source ->
      source
      |> EventSource.changeset(%{
        source_url: source_url,
        metadata: metadata,
        last_seen_at: now  # Always update to current time
      })
      |> Repo.update()
  end
end
```

### 2. Fixed the `QuizmeistersDetailJob` to Correctly Pass Source URLs

1. Rewrote the `fetch_venue_details` function in `quizmeisters_detail_job.ex` to ensure consistent URL handling:

```elixir
# Remember the original URL to ensure we update the same event source record
original_url = url

# Some URLs use quizmeisters.com.au and others use www.quizmeisters.com
# Normalize to use HTTPS and make sure we're handling both domains
url = 
  if String.contains?(url, "quizmeisters.com.au") do
    url
  else
    String.replace(url, "www.quizmeisters.com", "quizmeisters.com.au")
  end
    |> String.replace("http://", "https://")
```

2. Made sure to use the original URL when building the event data:

```elixir
# Create complete event data with all required fields
complete_event_data = %{
  # ... other fields ...
  # Use the original URL to ensure we update the correct event source
  source_url: original_url,
  # ... other fields ...
}
```

## Testing and Verification

Created and ran several test scripts to verify the fix:

1. `lib/scripts/test_quizmeisters_timestamp.exs` - Tests updating a single venue's timestamp
2. `lib/scripts/check_quizmeisters_timestamps.exs` - Checks the latest timestamps in the database
3. `lib/scripts/run_quizmeisters_scraper.exs` - Triggers the full Quizmeisters scraper and checks results

The tests confirmed that the timestamps are now updating correctly, with the most recent timestamps showing as `2025-03-22 10:24:15Z` for recently scraped venues.

## Conclusion

The timestamp updating mechanism now works correctly. When a venue is scraped by the Quizmeisters scraper, its `last_seen_at` timestamp is consistently updated in the `event_sources` table, even if there are no changes to the event data.

This ensures that administrators can accurately see when venues were last checked by the scraper, and the frontend can display up-to-date information about when venues were last verified. 
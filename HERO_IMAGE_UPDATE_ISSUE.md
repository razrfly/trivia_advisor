# Hero Image Update Logic Analysis

## Problem Summary

When a venue is scraped, we encounter an issue with hero image handling. The existing flow works as follows:

1. When force_refresh_images=true, old images are properly deleted from both the filesystem and database
2. New images are not being re-added to either the event record or filesystem
3. This occurs even when:
   - The image URL has changed completely
   - The old image has been deleted successfully
   - force_refresh_images flag is set to true

The fundamental issue is that **new hero images aren't being added even when they should be**, regardless of the force_refresh_images flag. This flag just ensures we delete old images first, but the core problem is that new images aren't being processed correctly afterward.

## Analysis of Image Update Flow

After auditing the code, I've identified several potential issues:

### Issue 1: Event Change Detection Logic

In `EventStore.event_changed?/2` function, hero_image is excluded from the comparison:

```elixir
defp event_changed?(event, attrs) do
  Map.take(event, [:start_time, :frequency, :entry_fee_cents, :description]) !=
  Map.take(attrs, [:start_time, :frequency, :entry_fee_cents, :description])
end
```

This means that even when a new hero_image is in the attrs, the function returns false if other fields haven't changed, preventing the event update entirely.

### Issue 2: Fragmented Event Update Flow

The current code has multiple update paths for events:

1. Direct performer_id update path
2. Normal event processing path
3. Special handling for existing events 

This creates potential gaps where hero_image updates can be missed, especially when only updating performer_id.

### Issue 3: Process Dictionary Value Inconsistency

Task processes (which handle image downloads and event processing) don't inherit process dictionary values. While there are attempts to pass force_refresh_images explicitly, there might be inconsistencies in how this value is propagated through nested function calls.

### Issue 4: Disconnect Between Image Deletion and Addition

Image deletion happens at multiple points (directly in QuizmeistersDetailJob and via EventStore), but there's no guaranteed connection between these deletion operations and subsequent image addition attempts.

## Strategy for Fix

### Primary Fix: Include hero_image in event change detection

Modify the `event_changed?/2` function in EventStore to include hero_image_url in the comparison:

```elixir
defp event_changed?(event, attrs) do
  # Get the event source to access hero_image_url from metadata
  event_source = Repo.get_by(EventSource, event_id: event.id)
  current_hero_image_url = if event_source, do: get_in(event_source.metadata, ["hero_image_url"]), else: nil
  
  # New hero_image_url from attrs if present
  new_hero_image_url = attrs[:hero_image_url]
  
  # Compare other fields
  basic_fields_changed = Map.take(event, [:start_time, :frequency, :entry_fee_cents, :description]) !=
                         Map.take(attrs, [:start_time, :frequency, :entry_fee_cents, :description])
  
  # Check if hero_image_url changed
  hero_image_changed = current_hero_image_url != new_hero_image_url && !is_nil(new_hero_image_url)
  
  # Event changed if either basic fields or hero image changed
  basic_fields_changed || hero_image_changed
end
```

### Secondary Fix: Consolidate Event Update Logic

Refactor the multiple event update paths into a single consistent flow:

1. Always check if the hero_image needs updating, even if other fields haven't changed
2. Create a dedicated function to handle hero image updates specifically

### Tertiary Fix: Explicit Force Refresh Propagation

Ensure force_refresh_images is properly passed to all relevant functions, especially across Task boundaries:

1. Add explicit parameters rather than relying on process dictionary
2. Handle nil values consistently 
3. Add more comprehensive logging for better diagnostic capability

## Implementation Plan

1. First, modify EventStore.event_changed? to include hero_image_url comparison
2. Add specific logging before and after hero image processing to track image download attempts
3. Ensure force_refresh_images is consistently passed throughout the call chain
4. Add a failsafe to ensure images are always processed when hero_image_url has changed

This approach targets the root cause while minimizing changes to the overall flow. 
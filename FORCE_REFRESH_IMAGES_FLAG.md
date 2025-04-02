# Force Refresh Images Flag: Implementation Guide

## Problem Overview

The `force_refresh_images` flag is designed to force re-downloading of images regardless of whether they already exist locally. When this flag is set to `true`, all scrapers should:

1. Delete existing venue hero images from storage
2. Clear hero_image fields in the database
3. Ensure new images are downloaded fresh instead of using cached versions

We encountered persistent issues with this flag not correctly propagating through the job pipeline, causing images to not be refreshed despite the flag being set to `true`.

## Root Causes Identified

1. **Process Dictionary Limitations**: The flag was being stored in the process dictionary, but Process dictionaries don't automatically transfer to Task processes.

2. **Inconsistent Flag Handling**: Different modules were extracting the flag in inconsistent ways:
   - Some used `Map.get(args, "force_refresh_images", false)`
   - Others used the `RateLimiter.force_refresh_images?(args)` helper
   - Some had hardcoded values (`force_refresh_images = true`) overriding the flag

3. **String vs Atom Keys**: The flag was sometimes set using atom keys (:force_refresh_images) and accessed with string keys ("force_refresh_images") or vice versa.

4. **Task Process Isolation**: Tasks used for HTTP and processing run in separate processes that don't share the process dictionary with the parent process.

## Correct Implementation (from Quizmeisters)

The Quizmeisters scraper successfully implements flag propagation with these techniques:

### In Index Job (quizmeisters_index_job.ex):

```elixir
# Extract flag from args (both string and atom keys)
force_refresh_images = case Process.get(:job_args) do
  %{} = args ->
    # Get the flag value directly from args rather than using a helper
    flag_value = Map.get(args, "force_refresh_images", false) || Map.get(args, :force_refresh_images, false)
    # Log it explicitly for debugging
    Logger.info("🔍 DEBUG: Force refresh images flag extracted from index job args: #{inspect(flag_value)}")
    flag_value
  _ -> false
end

# Pass to detail jobs as STRING KEYS (critical for Oban serialization)
detail_args = %{
  "venue" => venue,
  "source_id" => source_id,
  "force_update" => force_update,
  "force_refresh_images" => force_refresh_images  # Use string key
}
```

### In Detail Job (quizmeisters_detail_job.ex):

```elixir
# Extract force_refresh_images flag with explicit default
force_refresh_images = Map.get(args, "force_refresh_images", false)

# CRITICAL: Set the flag explicitly in process dictionary
if force_refresh_images do
  Logger.info("⚠️ Force image refresh enabled - will refresh ALL images regardless of existing state")
  # Store in process dictionary for access in other functions
  Process.put(:force_refresh_images, true)
else
  # Explicitly set to false to ensure it's not using a stale value
  Process.put(:force_refresh_images, false)
end

# Log value for verification
Logger.info("📝 Process dictionary force_refresh_images set to: #{inspect(Process.get(:force_refresh_images))}")
```

### In Image Processing Functions:

```elixir
# CRITICAL: Explicitly capture the force_refresh_images value for the Task
# Process dictionary values don't transfer to Task processes
force_refresh_images = Process.get(:force_refresh_images, false)

# Create a task that explicitly captures the variable
event_task = Task.async(fn ->
  # Log inside task to verify we're using the captured variable
  Logger.info("⚠️ TASK is using force_refresh=#{inspect(force_refresh_images)} from captured variable")
  
  # Pass force_refresh_images explicitly as a keyword argument
  EventStore.process_event(venue, event_data, source_id, force_refresh_images: force_refresh_images)
end)
```

### When Downloading Images:

```elixir
# CRITICAL: Get force_refresh_images from process dictionary and pass explicitly
force_refresh_images = Process.get(:force_refresh_images, false)
Logger.info("⚠️ Processing hero image with force_refresh=#{inspect(force_refresh_images)}")

case ImageDownloader.download_event_hero_image(extracted_data.hero_image_url, force_refresh_images) do
  # ... handle result
end
```

## Implementation Checklist for All Scrapers

To ensure proper `force_refresh_images` handling in any scraper:

1. **Index Job**:
   - Extract flag from args using BOTH string and atom keys
   - Store in process dictionary AND explicitly pass to detail jobs
   - Use STRING KEYS when passing to detail jobs via Oban
   - Log values for debugging

2. **Detail Job**:
   - Extract flag from args with explicit default value
   - Set in process dictionary with explicit true/false (not passing the value directly)
   - Log the stored value for verification
   - Implement venue directory cleaning when flag is true

3. **Image Processing**:
   - Always EXPLICITLY CAPTURE the flag value before passing to Tasks
   - Do NOT rely on process dictionary within Tasks
   - Log captured value inside Task to verify it carried over
   - Pass flag explicitly to EventStore functions as keyword args

4. **Testing**:
   - Test with `force_refresh_images: true` and verify logs show `force_refresh: true`
   - Verify images are actually deleted and re-downloaded
   - Verify timestamps on image files change

## Common Pitfalls to Avoid

1. ❌ DO NOT use `RateLimiter.force_refresh_images?(args)` in detail jobs without extra verification
2. ❌ DO NOT assume process dictionary values transfer to Task processes
3. ❌ DO NOT hardcode `force_refresh_images = true` anywhere 
4. ❌ DO NOT pass the flag value directly to `Process.put` without conditional handling
5. ❌ DO NOT mix string and atom keys without proper handling

## Log Pattern to Verify Correct Implementation

You should see this pattern in logs when the flag is correctly propagated:

```
[info] ⚠️ Force image refresh enabled - will refresh ALL images regardless of existing state
[info] 📝 Process dictionary force_refresh_images set to: true
[info] 🧨 Force refresh enabled - cleaning venue images directory for [venue name]
[info] ⚠️ Processing hero image with force_refresh=true
[info] 📸 Processing event hero image URL: [url], force_refresh: true
[info] 📥 Downloading image from URL: [url], force_refresh: true
[info] 🔄 Force refreshing existing image at [path] because force_refresh=true
[info] 🗑️ Deleted existing image to force refresh
```

If you see `force_refresh: false` in the logs when it should be true, that indicates the flag isn't being correctly propagated through the system.

## Execution Order Requirements

1. Set flag in index job and pass to detail job
2. Set flag in detail job process dictionary
3. Extract flag before each Task and explicitly capture it
4. Pass flag explicitly to all image processing functions
5. Delete existing images BEFORE attempting to download new ones

Following this guide will ensure consistent behavior across all scrapers. 
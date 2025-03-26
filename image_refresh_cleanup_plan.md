# QuizmeistersDetailJob Image Refresh Logic Cleanup

## Current State Analysis

The `QuizmeistersDetailJob` module currently contains redundant and scattered logic for handling image refresh operations. After running tests, we discovered that only some methods of passing the `force_refresh_images` parameter are actually working.

### Test Results

1. **Step 1 & 2: Direct parameter passing to ImageDownloader.download_event_hero_image**
   - ✅ WORKS: Directly passing `force_refresh=true` to download methods works correctly
   - Images are properly refreshed when called directly with this parameter

2. **Step 3: Process dictionary approach**
   - ❌ FAILS: Setting `force_refresh_images` in Process dictionary does NOT work across Task boundaries
   - The process dictionary value is seen as `nil` in the Task process

3. **Step 4: QuizmeistersDetailJob.process_hero_image approach**
   - ✅ WORKS: Explicitly capturing the `force_refresh_images` in closures and passing it to tasks works
   - This is the approach that should be kept and standardized

### Current Issues

1. **Ineffective Process Dictionary Usage**
   - The code sets values in Process dictionary but these don't transfer to Tasks
   - Redundant Process dictionary code should be removed

2. **Redundant Implementations**
   - Both `QuizmeistersDetailJob.safe_download_performer_image` and `ImageDownloader.safe_download_performer_image` exist
   - Multiple methods for handling image downloads with slightly different implementations

3. **Inconsistent Parameter Handling**
   - Some functions explicitly pass `force_refresh_images`
   - Others try to retrieve it from Process dictionary
   - Mixture of approaches leads to confusing code and bugs

4. **Excessive Logging and Comments**
   - Many debug logs for tracking force_refresh parameter values
   - Verbose comments explaining simple operations

## Goals for Cleanup

1. Keep only the approaches that demonstrably work (direct parameter passing + explicit capture in Tasks)
2. Remove all Process dictionary usage for force_refresh_images
3. Standardize on consistently passing parameters through function chains
4. Make the code more maintainable and in line with other Oban job implementations

## Implementation Plan

### 1. Remove Process Dictionary Usage

```elixir
# Remove all of these from the perform function:
if force_refresh_images do
  Logger.info("⚠️ Force image refresh enabled - will refresh ALL images regardless of existing state")
  Process.put(:force_refresh_images, true)
else
  Process.put(:force_refresh_images, false)
end

Logger.info("📝 Process dictionary force_refresh_images set to: #{inspect(Process.get(:force_refresh_images))}")
```

### 2. Update Function Signatures

Update the function chain to pass parameters explicitly:

```
perform(%Oban.Job{...args}) 
  -> process_venue(location, source, force_refresh_images)
    -> fetch_venue_details(venue_data, source, force_refresh_images)
      -> safe_download_performer_image(url, force_refresh_images)
      -> process_hero_image(hero_image_url, force_refresh_images)
```

### 3. Standardize Image Download Methods

Keep the explicit parameter capture for Tasks, but remove redundant code:

```elixir
# Keep this pattern that works
task = Task.async(fn ->
  # Explicitly capture and log the value being used
  Logger.info("Using force_refresh=#{inspect(force_refresh_images)}")
  ImageDownloader.download_event_hero_image(url, force_refresh_images)
end)
```

### 4. Remove Fallbacks to Process Dictionary

Remove code that falls back to Process dictionary values:

```elixir
# Remove this pattern:
force_refresh_images =
  if is_nil(force_refresh_images) do
    Process.get(:force_refresh_images, false)
  else
    force_refresh_images
  end
```

### 5. Clean Up Excessive Logging

- Remove all debug logging about Process dictionary values
- Keep only operational logs that provide useful information
- Standardize log levels

### 6. Consider Consolidating Helper Functions

- Consider moving `safe_download_performer_image` entirely to the `ImageDownloader` module
- Standardize common timeout and Task handling patterns

## Verification Steps

1. Ensure the existing test case continues to pass after changes, specifically test step 4
2. Run the direct test to confirm images are still refreshed properly
3. Check that we've eliminated redundant code while maintaining functionality

## Implementation Priority

1. First remove all Process dictionary usage
2. Update function signatures to pass parameters explicitly
3. Clean up redundant implementations
4. Reduce excessive logging
5. Verify with the test

## Summary

Our cleanup will focus on keeping the working method (explicit parameter passing with Task capture) while removing the non-working approach (Process dictionary). This will:

1. Make the code more maintainable by eliminating confusion about what's actually working
2. Remove redundant and ineffective code
3. Standardize on a consistent, working pattern
4. Keep the code thread-safe for Task operations

These changes will preserve critical functionality while making the code cleaner and more inline with best practices.

## Implementation Results

We have successfully implemented the changes described above:

1. ✅ **Removed Process Dictionary Usage**
   - Removed all `Process.put` and `Process.get` calls for force_refresh_images
   - Instead explicitly pass the parameter through the function chain

2. ✅ **Updated Function Signatures**
   - Modified `process_venue` to accept `force_refresh_images` parameter
   - Modified `process_event_with_performer` to accept the parameter
   - Made `process_hero_image` public for testing

3. ✅ **Standardized Image Download Approach**
   - Consistently use explicit parameter passing with Task capture
   - Simplified function implementations

4. ✅ **Removed Redundant Code**
   - Removed all fallbacks to Process dictionary values
   - Simplified conditional logic for handling force_refresh parameter

5. ✅ **Cleaned Up Logging**
   - Reduced excessive debug logging
   - Kept operational logs for important events
   - Made log messages clearer and more concise

6. ✅ **Verified with Tests**
   - Updated the test script to match our new approach
   - Verified that all test steps work correctly with our changes
   - All steps of the test now successfully refresh images when needed

The code is now more maintainable, thread-safe, and follows better functional programming practices by explicitly passing parameters instead of relying on process-local state that doesn't transfer across Task boundaries. 
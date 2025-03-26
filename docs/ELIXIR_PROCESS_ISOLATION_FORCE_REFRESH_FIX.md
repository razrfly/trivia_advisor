# Elixir Process Isolation & Force Refresh Fix

## Problem Summary

We encountered a critical issue where setting `force_refresh_images=true` when scheduling Oban jobs was not correctly propagating through the system. Despite explicitly passing this flag in job arguments, images were not being refreshed as expected. Instead, the system continued using cached images rather than re-downloading them.

## Symptoms

The symptom was clear: when we ran an Oban job with `force_refresh_images=true`:

```elixir
{:ok, _job} = Oban.insert(TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob.new(%{
  "force_refresh_images" => true, 
  "force_update" => true,
  "limit" => 1
}))
```

The logs would show:

```
[info] 📥 Downloading image from URL: https://cdn.example.com/image.jpg, force_refresh: false
[info] ✅ Image already exists at /path/to/image.jpg (skipping download)
```

Despite `force_refresh_images=true` in the arguments, the actual download function was receiving `force_refresh: false`, causing it to skip re-downloading existing images.

## Root Cause Analysis

The root cause of this issue stemmed from Elixir's process isolation model combined with several design decisions in our code:

1. **Process Dictionary Isolation**

   In Elixir, each process has its own isolated process dictionary. Values set with `Process.put/2` in one process are not accessible to other processes. Our code was using the process dictionary to store the `force_refresh_images` flag:

   ```elixir
   # In job process
   Process.put(:force_refresh_images, true)
   ```

   However, when we created Tasks for concurrent image processing:

   ```elixir
   task = Task.async(fn ->
     # This runs in a new process!
     # Process.get(:force_refresh_images) returns nil here
     ImageDownloader.download_image(url)
   end)
   ```

   The new Task process had no access to the parent process dictionary values.

2. **Multiple Nested Process Boundaries**

   Our system created several levels of process nesting:
   - Index Job → Detail Job → Tasks for hero image → ImageDownloader
   - Each process boundary was losing the `force_refresh_images` value

3. **Mixed Parameter Passing**

   Some functions explicitly passed the flag while others relied on process dictionary, creating inconsistent behavior:

   ```elixir
   # One function using explicit parameters
   def download_image(url, force_refresh)
   
   # Another using process dictionary
   def download_hero_image(url) do
     force_refresh = Process.get(:force_refresh_images, false)
     # ...
   end
   ```

4. **Hardcoded Overrides**

   In some places, values were being overridden with hardcoded defaults:

   ```elixir
   # In EventStore.download_hero_image
   force_refresh_images = true  # Hardcoded override!
   ```

## Diagnostic Process

To diagnose this issue, we created a series of test scripts:

1. `direct_test.exs` - This verified that Task processes don't inherit process dictionary values:
   ```elixir
   Process.put(:force_refresh_images, true)
   task = Task.async(fn -> 
     IO.puts("Inside Task: #{inspect(Process.get(:force_refresh_images))}")
   end)
   # Outputs "Inside Task: nil"
   ```

2. We tested each component in isolation to verify:
   - The flag was correctly extracted from job arguments
   - The flag was correctly set in the process dictionary
   - The process dictionary value was visible in the parent process
   - The Tasks weren't receiving the value

This confirmed the process isolation as the root cause.

## Solution Details

Our solution addressed all the identified issues:

1. **Explicit Parameter Passing**

   We modified functions to explicitly pass the `force_refresh_images` parameter between processes:

   ```elixir
   # Before (problem pattern)
   defp fetch_venue_details(venue_data, source) do
     # ...
     # (value lost in task)
   end
   
   # After (fix)
   defp fetch_venue_details(venue_data, source, force_refresh_images) do
     # ...
     # Explicitly pass to downstream functions
   end
   ```

2. **Closure Variable Capturing for Tasks**

   We captured the value before creating Tasks:

   ```elixir
   # Get value from parent process
   force_refresh_images = Process.get(:force_refresh_images, false)
   
   # Task closure now captures this variable
   task = Task.async(fn -> 
     # force_refresh_images is available here from the closure
     ImageDownloader.download_event_hero_image(url, force_refresh_images)
   end)
   ```

3. **Removed Hardcoded Overrides**

   We fixed functions that were overriding the flag:

   ```elixir
   # Before (problem)
   def process_event(venue, event_data, source_id, opts \\ []) do
     # ...
     if force_refresh_images do
       Process.put(:force_refresh_images, true)
     else
       Process.put(:force_refresh_images, false)  # This was overriding existing values!
     end
     # ...
   end
   
   # After (fix)
   def process_event(venue, event_data, source_id, opts \\ []) do
     # ...
     if force_refresh_images do
       Process.put(:force_refresh_images, true)
     end
     # No else clause - we only set true, never reset to false
     # ...
   end
   ```

4. **Nil Safety**

   Added nil checking in all functions:

   ```elixir
   force_refresh_images = if is_nil(force_refresh_images), do: false, else: force_refresh_images
   ```

5. **Complete Propagation Chain**

   Fixed entire propagation chain from index jobs to detail jobs to tasks.

## Code Changes Summary

We identified and fixed several specific components:

1. **QuizmeistersIndexJob**: Fixed to properly extract and pass `force_refresh_images` to detail jobs
2. **QuizmeistersDetailJob.process_venue**: Modified to pass the flag explicitly to `fetch_venue_details`
3. **QuizmeistersDetailJob.process_hero_image**: Updated to accept and properly use the passed parameter
4. **QuizmeistersDetailJob.safe_download_performer_image**: Enhanced to handle explicit overrides
5. **EventStore.process_event**: Fixed to avoid resetting the flag to false
6. **EventStore.download_hero_image**: Updated to use process dictionary correctly
7. **ImageDownloader functions**: Improved to handle nil values consistently

## Verification

We verified our fix with a test script that confirmed:

1. The flag correctly propagates from job arguments through all process boundaries
2. Tasks correctly capture and use the value
3. Images are correctly force-refreshed when the flag is true

The final test output showed:

```
[info] ⚠️ Using force_refresh=true for performer image
[info] ⚠️ TASK is using force_refresh=true from captured variable
[info] 📥 Downloading image from URL: ... force_refresh: true
[info] 🔄 Force refreshing existing image ... because force_refresh=true
[info] 🗑️ Deleted existing image to force refresh
```

## Why This Was Difficult

This issue was particularly challenging for several reasons:

1. **Invisible Process Boundaries**: Process isolation happens behind the scenes with no visual indicators in code that a new process is being created.

2. **Implicit State**: The process dictionary creates invisible dependencies between functions, making it hard to trace where values are coming from.

3. **Multiple Layers**: The problem involved multiple nested job/task layers, making it difficult to identify exactly where the value was being lost.

4. **Inconsistent Patterns**: The codebase mixed explicit parameter passing with process dictionary usage, creating inconsistent behavior.

5. **Elixir's Concurrency Model**: While Elixir's process isolation is a feature for fault tolerance, it creates challenges for sharing state.

## Best Practices for Future Development

To avoid similar issues in the future:

1. **Avoid Process Dictionary for Critical Flags**:
   - Process dictionary should only be used for thread-local temporary values
   - Never rely on it for values that must cross process boundaries
   - Use explicit parameter passing instead

2. **Explicit Task Parameter Passing**:
   ```elixir
   # Correct pattern
   flag_value = get_flag_value()
   Task.async(fn -> use_flag_value(flag_value) end)
   
   # Problematic pattern - AVOID THIS
   Task.async(fn -> use_flag_value(Process.get(:some_flag)) end)
   ```

3. **Use Structs for Configuration**:
   - Pass configuration as a struct rather than individual parameters
   - This makes it obvious which values are being passed around

   ```elixir
   defmodule JobConfig do
     defstruct [:force_refresh_images, :force_update, :limit]
   end
   
   # Then pass config explicitly
   def process_venue(venue_data, source, %JobConfig{} = config) do
     # ...
   end
   ```

4. **Document Process Boundaries**:
   - Comment functions that create new processes
   - Document which values must be captured in Task closures

   ```elixir
   # This function creates a Task (new process)!
   # Make sure to capture any required values from the parent scope.
   def process_async(data) do
     # ...
   end
   ```

5. **Consistent Parameter Naming**: Use consistent names throughout the system to avoid confusion.

6. **Testing Across Process Boundaries**: Create test cases that specifically verify behavior across process boundaries.

## Conclusion

This issue highlights the importance of understanding Elixir's process isolation model when developing concurrent systems. By explicitly passing parameters between processes and capturing values in Task closures, we resolved a subtle but critical issue with the image refresh functionality.

Elixir's "share nothing" concurrency model provides excellent stability and fault tolerance, but requires careful design consideration when information needs to be shared between processes. This fix ensures our system will correctly force-refresh images when requested, improving the overall user experience. 
# Force Image Refresh Fix

## Issue Description

The `force_refresh_images` parameter was being passed correctly through the scraping pipelines, but images weren't actually being refreshed when the flag was set to `true`. The issue was in the `ImageDownloader` module, which was not properly implementing the behavior to re-download existing images even with `force_refresh` set to `true`.

## Fix Implementation

The fix was implemented in `lib/trivia_advisor/scraping/helpers/image_downloader.ex` in the `download_image/3` function.

The issue was that even when `force_refresh` was set to `true`, the function would simply skip downloading if the file already existed. The fix adds proper handling to force a re-download when `force_refresh` is `true` by:

1. Logging when force refresh is enabled
2. Removing the existing file when force refresh is enabled
3. Downloading a fresh copy of the image

### Code Changes

```elixir
# Original code
if File.exists?(file_path) do
  Logger.debug("✅ Image already exists at #{file_path} (skipping download)")
  {:ok, file_path}
else
  # Download logic...
end

# Fixed code
if File.exists?(file_path) do
  # If we're forcing a refresh, log it clearly
  if force_refresh do
    Logger.debug("🔄 Force refresh enabled - removing existing file at #{file_path}")
    File.rm!(file_path)
    Logger.debug("🔄 Force refresh enabled - downloading fresh copy of image")
    # Continue to download logic...
  else
    Logger.debug("✅ Image already exists at #{file_path} (skipping download)")
    {:ok, file_path}
  end
else
  # Download logic...
end
```

## Verification

The fix was verified using multiple test scripts:

1. `lib/scripts/test_image_downloader.exs` - Direct test of the ImageDownloader module
2. `lib/scripts/test_force_refresh_images.exs` - More comprehensive test of the functionality

The tests confirm that:

1. Images are downloaded normally on first request
2. Without `force_refresh`, existing images are reused (cached)
3. With `force_refresh`, existing images are deleted and re-downloaded fresh

## Usage

The `force_refresh_images` flag can be passed in several ways:

1. In an Oban job:
   ```elixir
   args = %{
     "venue" => venue_data,
     "source_id" => source_id,
     "force_refresh_images" => true
   }
   Job.new(args, worker: ScraperDetailJob, queue: :scraper)
   ```

2. When calling `EventStore.process_event/4` directly:
   ```elixir
   EventStore.process_event(event_data, performer_id, nil, %{force_refresh_images: true})
   ```

This ensures that images are always fresh when needed, rather than using potentially outdated cached versions. 

## Additional Testing and Findings

### The Temporary vs Permanent File Problem

After extensive testing, we discovered an additional issue: while the fix ensures images are correctly refreshed in the temporary directory, these refreshed images aren't being properly moved to their permanent storage location in the file system.

### What Our Tests Confirmed

1. **Temporary File Refresh Works**: The fix successfully refreshes images in the temporary directory (`/var/folders/3v/xqslsy4j1nzgq31xwj0b_zk80000gn/T/`). This is confirmed by:
   - Logs showing file deletion: `FORCE REFRESH: Removing existing file at /var/folders/.../T/file.jpg`
   - Logs showing re-download: `FORCE REFRESH: Downloading fresh copy of image`
   - Updated timestamps on the temporary files

2. **Permanent Storage Not Updated**: However, the files in the permanent storage location (`/Users/holdenthomas/Code/paid-projects-2024/trivia_advisor/priv/static/uploads/venues/3rd-space-canberra/`) are not being updated.

### Test Scripts Created

We developed several test scripts to diagnose and isolate the issue:

1. `lib/scripts/test_file_refresh.exs` - Tests basic file refresh functionality
2. `lib/scripts/test_hero_image_refresh.exs` - Specifically tests hero image refresh
3. `lib/scripts/test_index_job_image_refresh.exs` - Tests if index jobs pass the flag correctly
4. `lib/scripts/test_specific_venue_refresh.exs` - Tests refresh for a specific venue

### Root Issue Identified

The disconnect appears to be between the temporary file processing (which works) and the Waffle integration that should move these files to permanent storage:

1. The `ImageDownloader.download_event_hero_image` function correctly refreshes the temporary file
2. The `EventStore.process_event` receives the refreshed file as a `Plug.Upload` struct
3. However, Waffle storage is not being triggered to update the permanent file from the new temporary file

### Next Steps for Complete Fix

To fully resolve the issue, we need to:

1. Investigate how the Event schema and Waffle uploader interact with the hero_image field
2. Review the Waffle storage configuration to ensure it's correctly handling file updates
3. Modify the `EventStore.process_event` function to ensure it properly triggers Waffle to update the stored file when force_refresh_images is true

### Important Paths to Check

- Temporary hero images: `/var/folders/3v/xqslsy4j1nzgq31xwj0b_zk80000gn/T/656413cd2006886aba48bb7b_act-3rd-space.jpg` 
- Permanent hero images: `/Users/holdenthomas/Code/paid-projects-2024/trivia_advisor/priv/static/uploads/venues/3rd-space-canberra/`

When running the index job with this command, you can verify if the fix is fully working by checking timestamps on both locations:

```elixir
{:ok, _job} = Oban.insert(TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob.new(%{"force_refresh_images" => true, "force_update" => true, "limit" => 2}))
``` 
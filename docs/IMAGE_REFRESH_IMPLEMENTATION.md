# Image Refresh Implementation Strategy

## Overview

This document outlines our strategy for implementing a robust force refresh mechanism for images in our TriviaAdvisor application. The core idea is to use Waffle's existing functionality while making minimal changes to the codebase.

## Background

We've identified that the system currently doesn't properly refresh images when requested. Images are cached locally, and we need a way to force the system to re-download images when needed (for example, when source images have changed, or when images were previously downloaded incorrectly).

## Implementation Strategy

Our strategy follows a "minimal change, maximum impact" approach:

1. **Use file deletion mechanism**: When `force_refresh=true`, we'll delete the existing image before attempting to download it, causing the system to treat it as a new image and therefore re-download it

2. **Leverage existing download pipeline**: After deletion, we'll let the existing download pipeline handle the actual downloading, avoiding the need to duplicate any of Waffle's functionality

3. **Ensure proper flag propagation**: We'll fix the existing issues with flag propagation across process boundaries (as documented in `ELIXIR_PROCESS_ISOLATION_FORCE_REFRESH_FIX.md`)

## Implementation Details

### 1. Image Deletion for Force Refresh

Add logic to `ImageDownloader` functions to:
- Check if `force_refresh=true`
- If the image already exists, delete it
- Let the normal download flow continue

```elixir
def download_image(url, force_refresh \\ false) do
  # Calculate destination path for the image
  path = calculate_destination_path(url)
  
  # Force refresh logic: If force_refresh=true and file exists, delete it
  if force_refresh and File.exists?(path) do
    Logger.info("🔄 Force refreshing existing image at #{path} because force_refresh=true")
    File.rm(path)
  end
  
  # Continue with existing download logic
  # (it will now detect the file as missing and download it)
  if File.exists?(path) and not force_refresh do
    # Existing logic for using cached image
    Logger.info("✅ Image already exists at #{path} (skipping download)")
    {:ok, %{path: path, filename: Path.basename(path)}}
  else
    # Existing logic for downloading image
    Logger.info("📥 Downloading image from URL: #{url}, force_refresh: #{force_refresh}")
    # Download logic...
  end
end
```

### 2. Target Functions for Modification

Modify the following functions:
- `ImageDownloader.download_image/2`
- `ImageDownloader.download_event_hero_image/2`
- `ImageDownloader.download_performer_image/2`

### 3. Flag Propagation

Ensure the `force_refresh` flag is properly propagated from:
- Oban job arguments
- Through all process boundaries (including Tasks)
- To the final download functions

## Testing Strategy

We need to verify three key aspects:

1. **Flag Propagation**: Verify the `force_refresh=true` flag correctly reaches the download functions
2. **Image Deletion**: Verify existing images are deleted when `force_refresh=true`
3. **Image Re-download**: Verify deleted images are properly re-downloaded

### Test Script

We'll create `force_refresh_verification_test.exs` to:

1. Download an image normally
2. Verify the image exists
3. Set `force_refresh=true`
4. Run the download with `force_refresh=true`
5. Check logs to verify force_refresh is set to true in the logs
6. Check filesystem to verify the image was deleted
7. Check filesystem to verify the image was re-downloaded with a new timestamp

```elixir
# Simplified example of verification test
defmodule ForceRefreshTest do
  require Logger
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

  @test_image_url "https://example.com/test-image.jpg"

  def run do
    # 1. Initial setup - normal download
    IO.puts("=== STEP 1: Initial normal download ===")
    {status, result} = ImageDownloader.download_event_hero_image(@test_image_url, false)
    image_path = result.path
    IO.puts("Image downloaded to: #{image_path}")
    
    # 2. Verify image exists and get initial timestamp
    initial_timestamp = get_file_timestamp(image_path)
    IO.puts("Image exists: #{File.exists?(image_path)}")
    IO.puts("Initial timestamp: #{format_timestamp(initial_timestamp)}")
    
    # 3. Wait a moment to ensure timestamp would be different
    :timer.sleep(1000)
    
    # 4. Run download with force_refresh=true
    IO.puts("\n=== STEP 2: Running with force_refresh=true ===")
    {status, result} = ImageDownloader.download_event_hero_image(@test_image_url, true)
    
    # 5. Verify image exists and check new timestamp
    new_timestamp = get_file_timestamp(image_path)
    IO.puts("Image exists after refresh: #{File.exists?(image_path)}")
    IO.puts("New timestamp: #{format_timestamp(new_timestamp)}")
    
    # 6. Verify timestamp changed (indicating file was deleted and re-created)
    if new_timestamp > initial_timestamp do
      IO.puts("\n✅ SUCCESS: Image was refreshed! Timestamp changed.")
    else
      IO.puts("\n❌ FAILURE: Image was NOT refreshed. Timestamp unchanged.")
    end
  end
  
  defp get_file_timestamp(path) do
    case File.stat(path) do
      {:ok, %{mtime: timestamp}} -> timestamp
      _ -> nil
    end
  end
  
  defp format_timestamp(nil), do: "N/A"
  defp format_timestamp(timestamp), do: "#{timestamp}"
end

# Run the test
ForceRefreshTest.run()
```

## Success Criteria

Our implementation is successful when:

1. **Correct Flag Value**: Logs show `force_refresh: true` when the flag is set
2. **Deletion Confirmation**: Logs show the file being deleted
3. **Re-download Confirmation**: 
   - Logs show the file being downloaded again
   - File timestamp is updated
   - Image is available after the operation

## Work Plan

1. Create and run baseline verification test to confirm current behavior
2. Implement force refresh logic in `ImageDownloader` functions
3. Run verification test to confirm fix is working
4. Document the changes and results
5. Create a pull request with the changes

## Limitations and Considerations

1. **Performance**: Force refreshing large numbers of images may put load on the image servers and consume bandwidth
2. **Error Handling**: Need to ensure proper error handling if file deletion fails
3. **Race Conditions**: Consider potential race conditions in concurrent environments

## Conclusion

This minimal-change approach leverages our existing architecture while adding the needed functionality to force refresh images. By deleting images before the normal download pipeline runs, we ensure that the system will treat them as new downloads without duplicating Waffle's functionality. 
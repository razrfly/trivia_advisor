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

## Step-by-Step Implementation

### 1. Index Job Implementation

Here's how to correctly implement the flag in the index job:

```elixir
def perform(%Oban.Job{args: args, id: job_id}) do
  # Store args in process dictionary for access in other functions
  Process.put(:job_args, args)

  # Extract the flag using both string and atom keys for robustness
  force_refresh_images = Map.get(args, "force_refresh_images", false) || 
                         Map.get(args, :force_refresh_images, false)
  
  # Set process dictionary explicitly based on value
  if force_refresh_images do
    Logger.info("⚠️ Force image refresh enabled - will refresh ALL images")
    Process.put(:force_refresh_images, true)
  else
    # Explicitly set to false to ensure it's not using a stale value
    Process.put(:force_refresh_images, false)
  end
  
  # Log the extracted value for debugging
  Logger.info("🔍 Force refresh images flag: #{inspect(force_refresh_images)}")
  
  # ... rest of function ...
end

# In the function that schedules detail jobs
defp enqueue_detail_jobs(venues, source_id) do
  # Extract the flag directly from job args, not process dictionary
  force_refresh_images = case Process.get(:job_args) do
    %{} = args ->
      # Get flag value from both string and atom keys
      flag_value = Map.get(args, "force_refresh_images", false) || 
                   Map.get(args, :force_refresh_images, false)
      flag_value
    _ -> false
  end
  
  # Log the value being passed to detail jobs
  Logger.info("🔍 Will pass force_refresh_images=#{inspect(force_refresh_images)} to detail jobs")
  
  # Use the RateLimiter to schedule jobs
  RateLimiter.schedule_detail_jobs(
    venues_to_process,
    DetailJobModule,
    fn venue ->
      # IMPORTANT: Use string keys for Oban job args
      detail_args = %{
        "venue_data" => venue_data,
        "source_id" => source_id,
        "force_refresh_images" => force_refresh_images  # Pass as string key
      }
      
      # Optional: Log the first job's args for debugging
      if venue == List.first(venues_to_process) do
        Logger.debug("🔍 First detail job args: #{inspect(detail_args)}")
      end
      
      detail_args
    end
  )
end
```

### 2. Detail Job Implementation

Here's how to correctly implement the flag in the detail job:

```elixir
def perform(%Oban.Job{args: args, id: job_id}) do
  # Optional: Log the received args
  Logger.debug("📦 Received detail job args: #{inspect(args)}")
  
  # Extract required values
  venue_data = Map.get(args, "venue_data")
  source_id = Map.get(args, "source_id")
  
  # Extract force_refresh_images with explicit default
  force_refresh_images = Map.get(args, "force_refresh_images", false)
  
  # CRITICAL: Set the flag explicitly in process dictionary
  if force_refresh_images do
    Logger.info("⚠️ Force image refresh enabled - will refresh ALL images")
    Process.put(:force_refresh_images, true)
  else
    # Explicitly set to false to ensure it's not using a stale value
    Process.put(:force_refresh_images, false)
  end
  
  # Log the value for verification
  Logger.info("📝 Process dictionary force_refresh_images set to: #{inspect(Process.get(:force_refresh_images))}")
  
  # When passing to helper functions, pass explicitly as a parameter
  fetch_args = %{
    venue_data: venue_data, 
    force_refresh_images: Process.get(:force_refresh_images, false)
  }
  
  # Call helper function with explicit parameter passing
  result = process_venue(fetch_args, source_id)
  
  # ... rest of function ...
end

# Helper function must accept the flag as a parameter
defp process_venue(%{venue_data: venue_data, force_refresh_images: force_refresh_images}, source_id) do
  # Use the explicitly passed parameter, not process dictionary
  if force_refresh_images do
    # Clean up existing images
    clean_venue_images(venue_data["name"])
  end
  
  # Process images with explicit flag passing
  hero_image_attrs = process_hero_image(venue_data["hero_image_url"], force_refresh_images)
  
  # ... rest of function ...
  
  # CRITICAL: Use Task with explicit variable capture
  event_task = Task.async(fn ->
    # Log inside task to verify value
    Logger.info("⚠️ TASK is using force_refresh=#{inspect(force_refresh_images)}")
    
    # Pass as keyword arg to EventStore.process_event
    EventStore.process_event(venue, event_data, source_id, 
                           force_refresh_images: force_refresh_images)
  end)
  
  # ... rest of function ...
end
```

### 3. Image Directory Cleaning

Here's how to clean venue image directories when the flag is true:

```elixir
# Implement in the detail job
if force_refresh_images do
  # Get venue slug for directory path
  venue_slug = venue.slug
  
  # Log the operation
  Logger.info("🧨 Force refresh enabled - cleaning venue images directory for #{venue.name}")
  
  # Construct the directory path
  venue_images_dir = Path.join(["priv/static/uploads/venues", venue_slug])
  
  # Check if directory exists before attempting to clean it
  if File.exists?(venue_images_dir) do
    # Get a list of image files in the directory
    case File.ls(venue_images_dir) do
      {:ok, files} ->
        image_extensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"]
        
        # Filter to only include image files
        image_files = Enum.filter(files, fn file ->
          ext = Path.extname(file) |> String.downcase()
          Enum.member?(image_extensions, ext)
        end)
        
        # Delete each image file
        Enum.each(image_files, fn image_file ->
          file_path = Path.join(venue_images_dir, image_file)
          Logger.info("🗑️ Deleting image file: #{file_path}")
          
          case File.rm(file_path) do
            :ok -> 
              Logger.info("✅ Successfully deleted image file: #{file_path}")
            {:error, reason} ->
              Logger.error("❌ Failed to delete image file: #{file_path} - #{inspect(reason)}")
          end
        end)
        
        # Log summary
        Logger.info("🧹 Cleaned #{length(image_files)} image files from #{venue_images_dir}")
        
        # Also clear hero_image field in database if it exists
        existing_event = find_existing_event(venue.id, day_of_week)
        if existing_event && existing_event.hero_image do
          existing_event
          |> Ecto.Changeset.change(%{hero_image: nil})
          |> Repo.update()
        end
      
      {:error, reason} ->
        Logger.error("❌ Failed to list files in directory #{venue_images_dir}: #{inspect(reason)}")
    end
  else
    Logger.info("⚠️ No existing venue images directory found at #{venue_images_dir}")
  end
end
```

### 4. Image Download with Force Refresh

The `ImageDownloader` module already implements force refresh correctly:

```elixir
if force_refresh and File.exists?(path) do
  Logger.info("🔄 Force refreshing existing image at #{path}")
  # Delete the existing file to ensure a fresh download
  File.rm!(path)
  Logger.info("🗑️ Deleted existing image to force refresh")
end
```

## Important Guidelines

1. **Always use string keys for Oban job args**:
   ```elixir
   # CORRECT
   %{"force_refresh_images" => true}
   
   # INCORRECT - avoid atom keys in Oban jobs
   %{force_refresh_images: true}
   ```

2. **Always pass force_refresh_images explicitly to Tasks**:
   ```elixir
   # CORRECT
   force_refresh_images = Process.get(:force_refresh_images, false)
   Task.async(fn ->
     EventStore.process_event(venue, event_data, source_id, 
                             force_refresh_images: force_refresh_images)
   end)
   
   # INCORRECT - process dictionary not available in Task
   Task.async(fn ->
     force_refresh_images = Process.get(:force_refresh_images, false)
     EventStore.process_event(venue, event_data, source_id, 
                             force_refresh_images: force_refresh_images)
   end)
   ```

3. **Use explicit parameter passing between functions**:
   ```elixir
   # CORRECT - pass as parameter
   fetch_args = %{
     venue_data: venue_data, 
     force_refresh_images: Process.get(:force_refresh_images, false)
   }
   process_venue(fetch_args, source_id)
   
   # INCORRECT - relying on process dictionary
   process_venue(venue_data, source_id)
   ```

4. **Set process dictionary values with explicit conditionals**:
   ```elixir
   # CORRECT
   if force_refresh_images do
     Process.put(:force_refresh_images, true)
   else
     Process.put(:force_refresh_images, false)
   end
   
   # INCORRECT - directly using the value
   Process.put(:force_refresh_images, force_refresh_images)
   ```

5. **Check both string and atom keys for robustness**:
   ```elixir
   # CORRECT - handles both formats
   force_refresh_images = Map.get(args, "force_refresh_images", false) || 
                          Map.get(args, :force_refresh_images, false)
   
   # INCOMPLETE - only handles string keys
   force_refresh_images = Map.get(args, "force_refresh_images", false)
   ```

## Implementation Checklist

### Index Job:
- [ ] Extract flag from args using both string and atom keys
- [ ] Set process dictionary explicitly with conditional (true/false)
- [ ] Pass flag to detail jobs using string keys
- [ ] Add logging of flag value before passing to detail jobs

### Detail Job:
- [ ] Extract flag from args with explicit default value
- [ ] Set process dictionary explicitly with conditional (true/false)
- [ ] Pass flag explicitly to helper functions as parameter
- [ ] Implement venue directory cleaning when flag is true
- [ ] Use Task with explicit variable capture for EventStore.process_event
- [ ] Add adequate logging for debugging

### Testing:
- [ ] Test with index job command: `{:ok, _job} = Oban.insert(ModuleName.new(%{"force_refresh_images" => true, "limit" => 1}))`
- [ ] Verify logs show `force_refresh: true` throughout the pipeline
- [ ] Verify images are deleted and re-downloaded

## Complete Example Command

```elixir
# Run with force refresh enabled
{:ok, _job} = Oban.insert(TriviaAdvisor.Scraping.Oban.ModuleNameIndexJob.new(%{
  "force_update" => true, 
  "force_refresh_images" => true,
  "limit" => 1
}))
```

Following this guide will ensure consistent behavior across all scrapers. 
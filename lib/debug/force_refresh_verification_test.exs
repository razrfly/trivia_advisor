# Force Refresh Verification Test Script
#
# This script tests:
# 1. Whether force_refresh=true flag is correctly propagated through the system
# 2. Whether images are properly deleted when force_refresh=true is used
# 3. Whether images are properly re-downloaded after deletion
#
# Run with: mix run lib/debug/force_refresh_verification_test.exs

require Logger
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

# Test URL - we'll use a consistent real image URL so we don't hit rate limits
test_image_url = "https://cdn.prod.website-files.com/61ea3abbe6d146ba89ea13d7/655aadddaced22f21dc76fca_qld%20-%2010%20toes.jpg"

IO.puts("\n========== FORCE REFRESH VERIFICATION TEST ==========")
IO.puts("This test verifies the force_refresh functionality for images")
IO.puts("=========================================================\n")

# ===== STEP 1: Initial setup - download image normally to ensure it exists =====

IO.puts("STEP 1: Initial download with force_refresh=false")
IO.puts("---------------------------------------------------")

{status, result} = ImageDownloader.download_event_hero_image(test_image_url, false)
image_path = result.path
filename = result.filename

# Verify initial download worked
IO.puts("Initial download status: #{inspect(status)}")
IO.puts("Downloaded image path: #{image_path}")
IO.puts("File exists: #{File.exists?(image_path)}")

# Get initial file stats
case File.stat(image_path) do
  {:ok, stats} ->
    initial_size = stats.size
    initial_mtime = stats.mtime

    IO.puts("Initial file size: #{initial_size} bytes")
    IO.puts("Initial timestamp: #{NaiveDateTime.to_string(NaiveDateTime.from_erl!(initial_mtime))}")

    # Wait to ensure timestamp would change on re-download
    IO.puts("\nWaiting 2 seconds to ensure timestamp difference...")
    :timer.sleep(2000)

    # ===== STEP 2: Run download with force_refresh=true =====

    IO.puts("\nSTEP 2: Downloading with force_refresh=true")
    IO.puts("-------------------------------------------")

    # We'll log more details during the download process to track the force_refresh flag
    Logger.info("⚠️ Starting download with force_refresh=true")

    # Run download with force_refresh=true
    {refresh_status, refresh_result} = ImageDownloader.download_event_hero_image(test_image_url, true)

    IO.puts("Force refresh download status: #{inspect(refresh_status)}")

    # Check if the file still exists
    IO.puts("File exists after refresh: #{File.exists?(image_path)}")

    # Check if the file was modified
    case File.stat(image_path) do
      {:ok, new_stats} ->
        new_size = new_stats.size
        new_mtime = new_stats.mtime

        IO.puts("New file size: #{new_size} bytes")
        IO.puts("New timestamp: #{NaiveDateTime.to_string(NaiveDateTime.from_erl!(new_mtime))}")

        # Compare before/after to verify the file was refreshed
        timestamp_changed = NaiveDateTime.compare(
          NaiveDateTime.from_erl!(new_mtime),
          NaiveDateTime.from_erl!(initial_mtime)
        ) == :gt

        if timestamp_changed do
          IO.puts("\n✅ SUCCESS: Image was refreshed! Timestamp is newer.")
        else
          IO.puts("\n❌ FAILURE: Image was NOT refreshed. Timestamp unchanged.")
        end

      _ ->
        IO.puts("\n❌ ERROR: Unable to get file stats after refresh")
    end

  _ ->
    IO.puts("❌ ERROR: Unable to get initial file stats")
end

# ===== STEP 3: Test with a task (simulates actual usage) =====

IO.puts("\nSTEP 3: Testing force_refresh in a Task")
IO.puts("---------------------------------------")

# Set up process flag to test propagation
Process.put(:force_refresh_images, true)
IO.puts("Process dictionary force_refresh_images: #{inspect(Process.get(:force_refresh_images))}")

# This simulates how the actual code runs in the application
task = Task.async(fn ->
  # This should now properly capture the value in the task
  force_refresh = Process.get(:force_refresh_images, false)
  Logger.info("⚠️ In Task - force_refresh value: #{inspect(force_refresh)}")

  # Run download
  ImageDownloader.download_event_hero_image(test_image_url, force_refresh)
end)

{task_status, task_result} = Task.await(task)

IO.puts("Task download status: #{inspect(task_status)}")

# ===== CONCLUSION =====

IO.puts("\n========== TEST COMPLETE ==========")
IO.puts("Check the logs above to verify:")
IO.puts("1. force_refresh=true was correctly passed to ImageDownloader")
IO.puts("2. The file was deleted when force_refresh=true")
IO.puts("3. The file was re-downloaded with a new timestamp")
IO.puts("====================================")

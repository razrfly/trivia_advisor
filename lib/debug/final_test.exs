# Simple direct test for the final solution to the force_refresh_images issue
# This script DIRECTLY tests both the process dictionary passing issue and the
# direct passing of force_refresh_images=true to specific functions

require Logger
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

# Test URLs - we'll use the same image URL for all tests to make comparison easier
image_url = "https://cdn.prod.website-files.com/61ea3abbe6d146ba89ea13d7/655aadddaced22f21dc76fca_qld%20-%2010%20toes.jpg"

IO.puts("\n===== FORCE REFRESH IMAGE DIRECT TEST =====")
IO.puts("This test will show if force_refresh=true is correctly maintained between processes")
IO.puts("and if our fix successfully ensures force_refresh_images works properly.\n")

# STEP 1: Basic setup - normal download to ensure the image exists first
IO.puts("STEP 1: Initial download with force_refresh=false")
IO.puts("-------------------------------------------------")
{status, result} = ImageDownloader.download_event_hero_image(image_url, false)
IO.puts("Results:")
IO.puts("  Status: #{inspect(status)}")
IO.puts("  Result: #{inspect(result.filename)}")
IO.puts("")

# STEP 2: Test direct parameter passing - this should always work
IO.puts("STEP 2: Direct parameter test with force_refresh=true")
IO.puts("-------------------------------------------------")
IO.puts("Calling with explicit force_refresh=true parameter...")
{status, _result} = ImageDownloader.download_event_hero_image(image_url, true)
IO.puts("Results:")
IO.puts("  Status: #{inspect(status)}")
IO.puts("")

# STEP 3: Test process dictionary with explicit value
IO.puts("STEP 3: Process dictionary test")
IO.puts("-------------------------------------------------")
# Set force_refresh_images in the process dictionary
Process.put(:force_refresh_images, true)
IO.puts("Process dictionary force_refresh_images value: #{inspect(Process.get(:force_refresh_images))}")

# Now create a task that will test downloading using the process dictionary value
task = Task.async(fn ->
  # Get the current process dictionary value
  current_value = Process.get(:force_refresh_images)
  Logger.info("⚠️ Process dictionary force_refresh_images for hero image: #{inspect(current_value)}")

  # Log if force refresh is enabled
  if current_value do
    Logger.info("🖼️ Processing hero image with FORCE REFRESH ENABLED")
  else
    Logger.info("🖼️ Processing hero image (normal mode)")
  end

  # Log the actual value
  Logger.info("🔍 Hero image force_refresh_images = #{inspect(current_value)}")

  # Create a task that explicitly captures the value
  inner_task = Task.async(fn ->
    # This should now properly capture the value from the lexical scope
    Logger.info("⚠️ HERO IMAGE TASK using force_refresh=#{inspect(current_value)}")
    ImageDownloader.download_event_hero_image(image_url, current_value)
  end)

  Task.await(inner_task)
end)

# Wait for the task to complete
Task.await(task)
IO.puts("")

# STEP 4: Test the hero image code specifically
IO.puts("STEP 4: Testing QuizmeistersDetailJob.process_hero_image")
IO.puts("-------------------------------------------------")
defmodule HeroImageTest do
  require Logger
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

  def run_test(image_url) do
    # Get force_refresh_images from process dictionary
    force_refresh_images = Process.get(:force_refresh_images, false)

    # Log the value for debugging
    Logger.info("⚠️ Process dictionary force_refresh_images for hero image: #{inspect(force_refresh_images)}")

    # Log clearly if force refresh is being used
    if force_refresh_images do
      Logger.info("🖼️ Processing hero image with FORCE REFRESH ENABLED")
    else
      Logger.info("🖼️ Processing hero image (normal mode)")
    end

    # Log the actual value for debugging
    Logger.info("🔍 Hero image force_refresh_images = #{inspect(force_refresh_images)}")

    # CRITICAL FIX: Create a task that explicitly captures the force_refresh_images value
    # to avoid issues with process dictionary not being available in the Task
    task = Task.async(fn ->
      # Log that we're using the captured variable
      Logger.info("⚠️ HERO IMAGE TASK using force_refresh=#{inspect(force_refresh_images)}")

      # Use centralized helper to download and process the image - pass the captured variable
      ImageDownloader.download_event_hero_image(image_url, force_refresh_images)
    end)

    # Wait for the task with a reasonable timeout
    case Task.yield(task, 30_000) || Task.shutdown(task) do
      {:ok, {:ok, upload}} ->
        Logger.info("✅ Successfully downloaded hero image")
        # Return both the hero_image and the original URL for reference
        %{hero_image: upload, hero_image_url: image_url}

      {:ok, {:error, reason}} ->
        Logger.warning("⚠️ Failed to download hero image: #{inspect(reason)}")
        # Return just the URL if we couldn't download the image
        %{hero_image_url: image_url}

      _ ->
        Logger.error("⏱️ Timeout downloading hero image from #{image_url}")
        %{hero_image_url: image_url}
    end
  end
end

# Run the hero image test
Process.put(:force_refresh_images, true)
IO.puts("Process dictionary force_refresh_images for hero image: #{inspect(Process.get(:force_refresh_images))}")
HeroImageTest.run_test(image_url)

IO.puts("\n===== TEST COMPLETE =====")
IO.puts("If ALL values reported were TRUE as expected, then our fix is working!")

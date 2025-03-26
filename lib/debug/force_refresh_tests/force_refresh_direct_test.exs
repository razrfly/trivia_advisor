# Direct test for force_refresh parameter passing in image download operations
# This script verifies that force_refresh=true is correctly maintained across function calls
#
# This uses the direct parameter approach where force_refresh_images is passed explicitly
# as a function parameter rather than using Process.put/get dictionary.

require Logger
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

# Test URLs - we'll use the same image URL for all tests to make comparison easier
image_url = "https://cdn.prod.website-files.com/61ea3abbe6d146ba89ea13d7/655aadddaced22f21dc76fca_qld%20-%2010%20toes.jpg"

IO.puts("\n===== FORCE REFRESH IMAGE DIRECT TEST =====")
IO.puts("This test verifies that force_refresh=true parameter is properly maintained")
IO.puts("across function calls and Tasks for image refresh operations.\n")

# STEP 1: Basic setup - normal download with force_refresh=false
IO.puts("STEP 1: Initial download with force_refresh=false")
IO.puts("-------------------------------------------------")
{status, result} = ImageDownloader.download_event_hero_image(image_url, false)
IO.puts("Results:")
IO.puts("  Status: #{inspect(status)}")
IO.puts("  Result: #{inspect(result.filename)}")
IO.puts("")

# STEP 2: Direct parameter passing with force_refresh=true
IO.puts("STEP 2: Direct parameter test with force_refresh=true")
IO.puts("-------------------------------------------------")
IO.puts("Calling with explicit force_refresh=true parameter...")
{status, _result} = ImageDownloader.download_event_hero_image(image_url, true)
IO.puts("Results:")
IO.puts("  Status: #{inspect(status)}")
IO.puts("")

# STEP 3: Test parameter capture in nested Tasks
IO.puts("STEP 3: Parameter capture in nested Tasks")
IO.puts("-------------------------------------------------")
force_refresh_images = true
IO.puts("Using force_refresh_images = #{inspect(force_refresh_images)}")

# Create a task that will then create another task - testing parameter capture across Task boundaries
task = Task.async(fn ->
  # Create a nested task that explicitly captures the parameter
  inner_task = Task.async(fn ->
    # The parameter should be properly captured in this closure
    ImageDownloader.download_event_hero_image(image_url, force_refresh_images)
  end)

  Task.await(inner_task)
end)

# Wait for the task to complete
Task.await(task)
IO.puts("")

# STEP 4: Test the QuizmeistersDetailJob.process_hero_image function
IO.puts("STEP 4: Testing QuizmeistersDetailJob.process_hero_image")
IO.puts("-------------------------------------------------")
defmodule HeroImageTest do
  require Logger
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

  def run_test(image_url) do
    # Test with explicit force_refresh=true
    force_refresh_images = true
    IO.puts("Testing with force_refresh_images = #{inspect(force_refresh_images)}")

    # Call the process_hero_image function directly
    result = QuizmeistersDetailJob.process_hero_image(image_url, force_refresh_images)

    # Return the result for inspection
    result
  end
end

# Run the hero image test
HeroImageTest.run_test(image_url)

IO.puts("\n===== TEST COMPLETE =====")
IO.puts("If force refresh is working correctly, all test steps should have")
IO.puts("shown a fresh download rather than using the cached image.")

# Final verification - this should use the cached image since force_refresh=false
{status, _} = ImageDownloader.download_event_hero_image(image_url, false)
IO.puts("Final check with force_refresh=false: #{inspect(status)}")

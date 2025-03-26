#!/usr/bin/env elixir

# This script is a minimal test that directly calls the ImageDownloader with
# force_refresh=true and false to observe the actual behavior

# Import all needed modules
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
require Logger

# Example image URL for testing
test_url = "https://cdn.prod.website-files.com/61ea3abbe6d146ba89ea13d7/655aadddaced22f21dc76fca_qld%20-%2010%20toes.jpg"

# Set logging level to info to see all relevant logs
Logger.configure(level: :info)

# Additional debugging - add a hook to output the args of all jobs
Oban.Testing.with_testing_mode(:manual, fn ->
  # Enable all job instrumentation
  :ok = Oban.Telemetry.attach_default_logger(:info)

  IO.puts("\n\n========= TESTING IMAGE DOWNLOADER WITH FORCE_REFRESH =========\n")

  # Manually test ImageDownloader with force_refresh=false
  IO.puts("\n======= First download with force_refresh=false =======")
  result_1 = ImageDownloader.download_event_hero_image(test_url, false)
  {:ok, file_1} = result_1

  stats_1 = File.stat!(file_1.path)
  IO.puts("File path: #{file_1.path}")
  IO.puts("Created at: #{inspect(stats_1.mtime)}")
  IO.puts("Size: #{stats_1.size} bytes")

  # Manually test ImageDownloader with force_refresh=true
  IO.puts("\n======= Second download with force_refresh=true =======")
  result_2 = ImageDownloader.download_event_hero_image(test_url, true)
  {:ok, file_2} = result_2

  stats_2 = File.stat!(file_2.path)
  IO.puts("File path: #{file_2.path}")
  IO.puts("Created at: #{inspect(stats_2.mtime)}")
  IO.puts("Size: #{stats_2.size} bytes")

  # Check if the file was actually re-downloaded (different timestamp)
  if stats_1.mtime != stats_2.mtime do
    IO.puts("\n✅ SUCCESS: force_refresh=true caused the file to be re-downloaded (timestamps differ)")
  else
    IO.puts("\n❌ FAIL: force_refresh=true did not cause the file to be re-downloaded (same timestamp)")
  end

  IO.puts("\nNow let's check what happens in the Oban job context...\n")

  # Schedule a job with force_refresh_images=true
  IO.puts("======= Inserting QuizmeistersIndexJob with force_refresh_images=true =======")
  args = %{
    "force_update" => true,
    "force_refresh_images" => true,
    "limit" => 1, # Limit to just 1 venue for quicker testing
    "test_mode" => true
  }

  # Execute the job
  {:ok, job} = Oban.insert(QuizmeistersIndexJob.new(args))
  IO.puts("Job inserted with ID: #{job.id}")

  # Tell the user what to look for in the logs
  IO.puts("Check the logs for force_refresh values in the job output.")
  IO.puts("You should see:")
  IO.puts("1. Process dictionary force_refresh_images set to: true")
  IO.puts("2. Process dictionary force_refresh_images value: true")
  IO.puts("3. TASK is using force_refresh=true from captured variable")
  IO.puts("4. force_refresh: true in the image download logs")
  IO.puts("5. HERO IMAGE TASK using force_refresh=true")

  # Print completion message
  IO.puts("\n========= TEST COMPLETED =========")
  IO.puts("The job is running in the background. Check the console output for the values mentioned above.")
end)

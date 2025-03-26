#!/usr/bin/env elixir

# Fixed Force Refresh Test
# This script tests the entire pipeline with the proper flag propagation after removing hardcoded values
# Run with: mix run lib/debug/test_fixed_force_refresh.exs

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
alias TriviaAdvisor.Events.EventStore
require Logger

Logger.configure(level: :info)

# Configure how many jobs to run for testing
limit = 1

IO.puts("\n\n========= TESTING FIXED FORCE REFRESH PIPELINE =========\n")
IO.puts("This script will test the fixed force refresh functionality by running a limited")
IO.puts("QuizmeistersIndexJob with force_refresh_images set to true, and verify that the")
IO.puts("flag is properly propagated through the entire pipeline without hardcoded values.\n")

# Add instrumentation to key functions to track the flag without modifying behavior

# Track the ImageDownloader.download_event_hero_image function
old_download_hero_image = Function.capture(TriviaAdvisor.Scraping.Helpers.ImageDownloader, :download_event_hero_image, 2)

defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  def download_event_hero_image(url, force_refresh) do
    # Log the force_refresh parameter
    Logger.info("🔍 TRACER: ImageDownloader.download_event_hero_image called with:")
    Logger.info("   - URL: #{url}")
    Logger.info("   - force_refresh: #{inspect(force_refresh)}")

    # Call the original function
    unquote(old_download_hero_image).(url, force_refresh)
  end
end

# Track the EventStore.process_event function
old_process_event = Function.capture(TriviaAdvisor.Events.EventStore, :process_event, 4)

defmodule TriviaAdvisor.Events.EventStore do
  def process_event(venue, event_data, source_id, opts \\ []) do
    # Log the opts parameter
    Logger.info("🔍 TRACER: EventStore.process_event called with:")
    Logger.info("   - Venue: #{venue["name"]}")
    Logger.info("   - Event: #{event_data["name"] || "unknown"}")
    Logger.info("   - force_refresh_images: #{inspect(Keyword.get(opts, :force_refresh_images, false))}")

    # Call the original function
    unquote(old_process_event).(venue, event_data, source_id, opts)
  end
end

# Track the QuizmeistersDetailJob.perform function
old_detail_perform = Function.capture(TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob, :perform, 1)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  def perform(%Oban.Job{id: job_id, args: args} = job) do
    # Log the args received by the detail job
    Logger.info("🔍 TRACER: QuizmeistersDetailJob.perform called with:")
    Logger.info("   - Job ID: #{job_id}")
    Logger.info("   - force_refresh_images: #{inspect(Map.get(args, "force_refresh_images", false))}")

    # Call the original function
    unquote(old_detail_perform).(job)
  end
end

# ========= Run the test =========

IO.puts("\n=== Running index job WITH force_refresh_images ===")
{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(%{
  "force_update" => true,
  "limit" => limit,
  "force_refresh_images" => true
}))

IO.puts("Inserted test job #{job.id} with force_refresh_images: true")
IO.puts("Check the logs to verify that force_refresh_images=true is correctly")
IO.puts("propagated all the way to the ImageDownloader without hardcoded values.\n")

IO.puts("========= TEST COMPLETED =========")
IO.puts("Look for '🔍 TRACER:' log entries to track the flag propagation.")
IO.puts("With the fixes applied, you should see force_refresh=true all the way through the pipeline.")

#!/usr/bin/env elixir

# Test script to verify force_refresh_images flag passing between jobs
# Run with: mix run lib/debug/test_force_refresh_images_in_jobs.exs

# Import required modules
alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
alias TriviaAdvisor.Events.EventStore
require Logger

# Add debug logging to trace flag values
Logger.configure(level: :debug)

# Monkey patch key functions to add instrumentation
# Note: These patches are just for diagnostics and don't change behavior

# Patch the RateLimiter.schedule_hourly_capped_jobs function
old_schedule_hourly_capped_jobs = Function.capture(TriviaAdvisor.Scraping.RateLimiter, :schedule_hourly_capped_jobs, 3)

defmodule TriviaAdvisor.Scraping.RateLimiter do
  def schedule_hourly_capped_jobs(items, job_module, args_fn) do
    # Get the first item's args for inspection
    if length(items) > 0 do
      first_item = List.first(items)
      first_args = args_fn.(first_item)
      Logger.info("🔍 DEBUG: First detail job args: #{inspect(first_args)}")
      
      # Check specifically for force_refresh_images
      force_refresh_images = Map.get(first_args, :force_refresh_images) || Map.get(first_args, "force_refresh_images", false)
      Logger.info("🔍 DEBUG: Force refresh images in detail job args: #{inspect(force_refresh_images)}")
    end
    
    # Call the original function
    unquote(old_schedule_hourly_capped_jobs).(items, job_module, args_fn)
  end
end

# Patch QuizmeistersDetailJob.perform to log args
old_detail_perform = Function.capture(TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob, :perform, 1)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  def perform(%Oban.Job{id: job_id, args: args} = job) do
    # Log the actual args received by the detail job
    Logger.info("🔍 DEBUG: Detail job received args: #{inspect(args)}")
    
    # Check specifically for force_refresh_images
    force_refresh_images = Map.get(args, "force_refresh_images", false)
    Logger.info("🔍 DEBUG: Force refresh images in detail job: #{inspect(force_refresh_images)}")
    
    # Call the original function
    unquote(old_detail_perform).(job)
  end
end

# Patch ImageDownloader.download_event_hero_image to log force_refresh parameter
old_download_hero_image = Function.capture(TriviaAdvisor.Scraping.Helpers.ImageDownloader, :download_event_hero_image, 2)

defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  def download_event_hero_image(url, force_refresh) do
    # Log the force_refresh parameter
    Logger.info("🔍 DEBUG: ImageDownloader.download_event_hero_image called with force_refresh: #{inspect(force_refresh)}")
    
    # Call the original function
    unquote(old_download_hero_image).(url, force_refresh)
  end
end

# Patch EventStore.process_event to log opts
old_process_event = Function.capture(TriviaAdvisor.Events.EventStore, :process_event, 4)

defmodule TriviaAdvisor.Events.EventStore do
  def process_event(venue, event_data, source_id, opts \\ []) do
    # Log the opts parameter
    Logger.info("🔍 DEBUG: EventStore.process_event called with opts: #{inspect(opts)}")
    
    # Check specifically for force_refresh_images
    force_refresh_images = Keyword.get(opts, :force_refresh_images, false)
    Logger.info("🔍 DEBUG: Force refresh images in EventStore.process_event: #{inspect(force_refresh_images)}")
    
    # Call the original function
    unquote(old_process_event).(venue, event_data, source_id, opts)
  end
end

# Run the test by inserting an index job with force_refresh_images set to true
IO.puts "Starting test of force_refresh_images flag propagation...\n"

{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(%{
  "force_refresh_images" => true, 
  "force_update" => true, 
  "limit" => 1
}))

IO.puts "\nInserted test job #{job.id} with force_refresh_images: true"
IO.puts "Check the logs to see if the flag is correctly passed to the detail job"
IO.puts "Test completed. Look for '🔍 DEBUG:' log entries to track the flag propagation."
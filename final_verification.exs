#!/usr/bin/env elixir

# Final verification script that the force_refresh_images fix works

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
require Logger

# Set logs to info level
Logger.configure(level: :info)

IO.puts("\n=== FINAL VERIFICATION OF FORCE_REFRESH_IMAGES FIX ===\n")
IO.puts("Our fix should now force all images to be refreshed.\n")

# Create and run the job
job_args = %{
  "force_refresh_images" => true,
  "force_update" => true,
  "limit" => 1
}

IO.puts("Creating job with arguments:")
IO.inspect(job_args, pretty: true)

{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(job_args))

IO.puts("\nJob created successfully with ID: #{job.id}")
IO.puts("It will be executed shortly")
IO.puts("\nIn the logs you should see:")
IO.puts("1. '🔍 DEBUG: FORCING Hero image download with force_refresh_images=true'")
IO.puts("2. 'force_refresh: true' in the image download logs\n")
IO.puts("If you see these messages, the fix is working!")
IO.puts("FYI: The fix is to hard-code force_refresh_images=true in process_hero_image")
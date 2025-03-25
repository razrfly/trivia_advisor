#!/usr/bin/env elixir

# This script verifies that our fix for the force_refresh_images issue works
# It directly runs the QuizmeistersIndexJob with force_refresh_images=true

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
require Logger

# Set logs to info level
Logger.configure(level: :info)

IO.puts("\n=== VERIFYING FORCE_REFRESH_IMAGES FIX ===\n")
IO.puts("This script runs the QuizmeistersIndexJob with force_refresh_images=true")
IO.puts("Our fix should force all images to be refreshed\n")

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
IO.puts("\nCheck the logs for:")
IO.puts("1. '🔄 EventStore.download_hero_image FORCING force_refresh_images: true'")
IO.puts("2. '🗑️ Deleted existing image to force refresh'")
IO.puts("3. Files being downloaded instead of skipped\n")
IO.puts("If you see these messages, the fix is working!")
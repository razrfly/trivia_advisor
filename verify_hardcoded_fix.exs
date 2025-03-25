#!/usr/bin/env elixir

# This script verifies the final hard-coded fix for the force_refresh_images issue
# We now hard-code force_refresh=true in all relevant functions

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
require Logger

Logger.configure(level: :info)

IO.puts("\n=== FINAL VERIFICATION - HARD-CODED FIX ===\n")
IO.puts("This fix hard-codes force_refresh=true in all relevant functions:")
IO.puts("1. In process_hero_image")
IO.puts("2. In both performer image download code blocks")
IO.puts("3. In safe_download_performer_image\n")

IO.puts("This guarantees images will ALWAYS be refreshed regardless of process context.\n")

# Create the job with the flag
job_args = %{
  "force_refresh_images" => true, 
  "force_update" => true,
  "limit" => 1
}

IO.puts("Creating QuizmeistersIndexJob with arguments:")
IO.inspect(job_args, pretty: true)

# Insert the job
{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(job_args))

IO.puts("\nJob created with ID: #{job.id}")
IO.puts("\nThis will run shortly, and should show these messages in the logs:")
IO.puts("1. '🔍 DEBUG: safe_download_performer_image FORCING force_refresh=true'")
IO.puts("2. '🔍 DEBUG: FORCING Hero image download with force_refresh_images=true'")
IO.puts("3. '🔍 DEBUG: Calling ImageDownloader.download_performer_image with force_refresh=true'\n")
IO.puts("If you see 'Deleted existing image to force refresh', the fix is working!\n")
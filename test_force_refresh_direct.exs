#!/usr/bin/env elixir

# Direct test script for QuizmeistersDetailJob force_refresh_images
# ---------------------------------------------------------------
# RUN AS: mix run test_force_refresh_direct.exs
# This script bypasses the index job and tests the detail job directly

alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo
require Logger

# Configure logging level
Logger.configure(level: :info)
IO.puts("\n=== TESTING FORCE_REFRESH_IMAGES FLAG ===")

# Get the Quizmeisters source
source = Repo.get_by!(Source, website_url: "https://quizmeisters.com")
source_id = source.id

# Test venue with existing known hero image
test_venue = %{
  "name" => "10 Toes Buderim",
  "address" => "15/3 Pittards Rd, Buderim, Queensland, 4556, AU",
  "custom_fields" => %{
    "trivia_night" => "Thursday 7:00 PM"
  },
  "url" => "https://www.quizmeisters.com/venues/qld-10-toes",
  "lat" => "-26.6630807",
  "lng" => "153.0518295",
  "postcode" => "4556"
}

# Set force_refresh_images to true
force_refresh_images = true
IO.puts("Setting force_refresh_images to: #{force_refresh_images}")

# Create detail job args directly with string keys
job_args = %{
  "venue" => test_venue,
  "source_id" => source_id,
  "force_update" => true,
  "force_refresh_images" => force_refresh_images
}

# Create the job
IO.puts("\nCreating QuizmeistersDetailJob with force_refresh_images=#{force_refresh_images}")
job = QuizmeistersDetailJob.new(job_args)

IO.puts("\nJob created. Now executing it directly...")
IO.puts("Look for these indicators in the logs:")
IO.puts(" - '🔄 Force refresh flag: true'")
IO.puts(" - '🔍 DEBUG: safe_download_performer_image called with force_refresh: true'")
IO.puts(" - '🔍 DEBUG: Hero image download using force_refresh_images: true'")
IO.puts(" - '🔄 Force refreshing existing image'")

# Execute the job with extended timeout
IO.puts("\nExecuting job. Please wait...")
Oban.Job.execute(job, timeout: 60_000)

IO.puts("\n=== TEST COMPLETED ===")
IO.puts("If you see 'Force refreshing existing image' messages, the fix is working!")
#!/usr/bin/env elixir

# This script tests the QuizmeistersDetailJob with our fix for the force_refresh_images issue
# The key fix is setting the process dictionary value within the Task.async block

alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo
require Logger

# Configure logging level
Logger.configure(level: :info)

IO.puts("\n=== TESTING QUIZMEISTERS DETAIL JOB WITH FORCE_REFRESH_IMAGES FIX ===")

# Get the Quizmeisters source
source = Repo.get_by!(Source, website_url: "https://quizmeisters.com")
source_id = source.id

# Test venue with known image URLs
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
IO.puts("Testing with force_refresh_images=#{force_refresh_images}")

# Create detail job with force_refresh_images=true
job_args = %{
  "venue" => test_venue,
  "source_id" => source_id,
  "force_update" => true,
  "force_refresh_images" => force_refresh_images
}

# Create the job
job = QuizmeistersDetailJob.new(job_args)

IO.puts("\nExecuting job directly...")
IO.puts("Look for these messages in the logs:")
IO.puts("1. '🚨 DEBUG (CRITICAL): Inside Task - Set force_refresh_images=true in process dictionary'")
IO.puts("2. '🔄 EventStore.download_hero_image using force_refresh_images: true'")
IO.puts("3. '🔄 Force refreshing existing image'")

# Execute the job
Oban.Job.execute(job, timeout: 60_000)

IO.puts("\n=== TEST COMPLETED ===")
IO.puts("Check the logs to verify whether force_refresh_images is properly propagated")
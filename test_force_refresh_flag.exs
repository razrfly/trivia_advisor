#!/usr/bin/env elixir

# This script tests the force_refresh_images flag propagation
# by directly running a Quizmeisters detail job for a single venue.

alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo
require Logger

Logger.configure(level: :info)

IO.puts "=== Testing Force Refresh Images Flag Propagation ==="

# Command line arg to determine if we should force refresh
force_refresh = System.argv() 
                |> Enum.member?("--force-refresh")

IO.puts "Force refresh enabled: #{force_refresh}"

# Get the Quizmeisters source
source = Repo.get_by!(Source, website_url: "https://quizmeisters.com")
source_id = source.id

# Test venue data (minimal required fields)
test_venue = %{
  "name" => "Test Venue",
  "address" => "123 Test Street",
  "custom_fields" => %{
    "trivia_night" => "Thursday 7:00 PM"
  },
  "url" => "https://www.quizmeisters.com.au/venues/test-venue",
  "fields" => [],
  "lat" => -33.8688,
  "lng" => 151.2093,
  "postcode" => "2000"
}

# Create test job with the force_refresh_images flag
job_args = %{
  "venue" => test_venue,
  "source_id" => source_id,
  "force_update" => true,
  "force_refresh_images" => force_refresh
}

IO.puts "Creating test job with args:"
IO.inspect job_args, pretty: true

# Create the job
job = TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob.new(job_args)

IO.puts "\nTest job created. ID: #{job.id}"
IO.puts "Args preserved in job:"
IO.inspect job.args, pretty: true
IO.puts ""

# Execute job directly (without queueing)
IO.puts "Executing job directly..."
case Oban.Job.execute(job) do
  {:ok, result} ->
    IO.puts "✅ Job completed successfully"
    IO.inspect result, label: "Result"
  
  {:error, error} ->
    IO.puts "❌ Job failed:"
    IO.inspect error
end

IO.puts "\nTest completed. Check logs for 'Force refresh flag:' entries."
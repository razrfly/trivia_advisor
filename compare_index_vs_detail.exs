#!/usr/bin/env elixir

# This script compares how arguments are passed from index to detail jobs
# It runs a parallel test of both approaches:
# 1. Direct detail job creation
# 2. Index job that creates detail jobs
# to help diagnose where force_refresh_images might be getting lost

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo
require Logger

Logger.configure(level: :info)

IO.puts "=== Comparing Index vs Direct Detail Job Creation ==="

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

# PART 1: Create detail job directly
IO.puts "\n=== 1. Creating detail job directly ==="
detail_args = %{
  "venue" => test_venue,
  "source_id" => source_id,
  "force_update" => true,
  "force_refresh_images" => true
}

IO.puts "Direct detail job args:"
IO.inspect detail_args, pretty: true

detail_job = QuizmeistersDetailJob.new(detail_args)
IO.puts "Detail job created with ID: #{detail_job.id}"
IO.puts "Args preserved in job:"
IO.inspect detail_job.args, pretty: true

# PART 2: Create an index job that will create a detail job
IO.puts "\n=== 2. Creating index job that should create a detail job ==="

# Patch the RateLimiter.schedule_hourly_capped_jobs function to log what args it's seeing
old_schedule_hourly_capped_jobs = Function.capture(TriviaAdvisor.Scraping.RateLimiter, :schedule_hourly_capped_jobs, 3)

defmodule TriviaAdvisor.Scraping.RateLimiter do
  def schedule_hourly_capped_jobs(items, job_module, args_fn) do
    # Get the first item and log what args_fn produces for it
    if length(items) > 0 do
      first_item = List.first(items)
      first_args = args_fn.(first_item)
      IO.puts "\n=== Args passed to detail job by index job: ==="
      IO.inspect first_args, pretty: true
      
      force_refresh_images = Map.get(first_args, :force_refresh_images) || Map.get(first_args, "force_refresh_images", false)
      IO.puts "force_refresh_images value: #{inspect(force_refresh_images)}"
      
      # Convert field to string key to see if that's the issue
      if Map.has_key?(first_args, :force_refresh_images) do
        IO.puts "\nWARNING: Using atom key (:force_refresh_images) but Oban jobs expect string keys!"
        IO.puts "This might be why the flag isn't being preserved."
      end
    end
    
    # Call the original function
    unquote(old_schedule_hourly_capped_jobs).(items, job_module, args_fn)
  end
end

# Patch Oban.insert to log what it's receiving
old_oban_insert = Function.capture(Oban, :insert, 1)

defmodule Oban do
  def insert(job) do
    # Log what's being inserted
    IO.puts "\n=== Detail job args as received by Oban.insert: ==="
    IO.inspect job.args, pretty: true
    
    # Check if force_refresh_images is present with the right key type
    has_string_key = Map.has_key?(job.args, "force_refresh_images")
    has_atom_key = Map.has_key?(job.args, :force_refresh_images)
    
    IO.puts "Has string key 'force_refresh_images': #{has_string_key}"
    IO.puts "Has atom key :force_refresh_images: #{has_atom_key}"
    
    if has_atom_key and not has_string_key do
      IO.puts "\nDIAGNOSIS: The issue is that detail job is receiving force_refresh_images as an atom key,"
      IO.puts "but Oban serializes job args to JSON, which converts all keys to strings."
      IO.puts "When the job is later executed, it's checking for the string key, not the atom key."
    end
    
    # Call the original function
    unquote(old_oban_insert).(job)
  end
end

index_args = %{
  "force_refresh_images" => true,
  "force_update" => true,
  "limit" => 1
}

IO.puts "Index job args:"
IO.inspect index_args, pretty: true

# Insert a test venue into the index job args for testing
# This will bypass the HTTP request in the index job
Process.put(:test_venues, [test_venue])

index_job = QuizmeistersIndexJob.new(index_args)
IO.puts "Index job created with ID: #{index_job.id}"
IO.puts "Args preserved in job:"
IO.inspect index_job.args, pretty: true

# PART 3: Compare the encoded job args to see if there's a difference
IO.puts "\n=== 3. Comparing JSON-encoded job args ==="
detail_encoded = Jason.encode!(detail_job.args)
index_encoded = Jason.encode!(index_job.args)

IO.puts "Detail job args encoded: #{detail_encoded}"
IO.puts "Index job args encoded: #{index_encoded}"

# Execute the index job (will create detail jobs)
IO.puts "\n=== Executing index job to see what detail jobs it creates ==="
Oban.Job.execute(index_job)

IO.puts "\nTest completed."
# Test script for GeeksWhoDrinkIndexJob
# Run with: mix run lib/debug/test_geeks_who_drink.exs

require Logger
alias TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob

# Configure logger to show info level and above
Logger.configure(level: :info)
IO.puts("\n\n====== TEST GEEKS WHO DRINK INDEX JOB ======")
IO.puts("🧪 Starting test with limit of 15 venues ONLY")
IO.puts("============================================\n")

# Clear all existing jobs to ensure we don't have any leftovers
Oban.drain_queue(queue: :default, with_scheduled: true)
IO.puts("✅ Cleared existing jobs")

# Allow a moment for everything to initialize
:timer.sleep(1000)

start_time = :os.system_time(:millisecond)

# Create job params with explicit limit
job_params = %{limit: 15}

# METHOD 1: Direct perform call (this won't insert the job in the DB but will run it in-process)
IO.puts("\n📝 DIRECT METHOD: Running GeeksWhoDrinkIndexJob.perform with limit=15...\n")

job = %Oban.Job{id: 999999, args: %{"limit" => 15}}
result = GeeksWhoDrinkIndexJob.perform(job)

end_time = :os.system_time(:millisecond)
duration = (end_time - start_time) / 1000

# Process the result
case result do
  {:ok, stats} ->
    IO.puts("\n✅ GeeksWhoDrinkIndexJob completed in #{duration} seconds")
    IO.puts("📊 Stats: Total venues: #{stats.venue_count}, Enqueued: #{stats.enqueued_jobs}, Skipped: #{stats.skipped_venues}")

    # Verify the limit was applied correctly
    if stats.enqueued_jobs <= 15 do
      IO.puts("\n========== PASS ==========")
      IO.puts("Successfully processed #{stats.enqueued_jobs} venues with limit of 15")
    else
      IO.puts("\n========== FAIL ==========")
      IO.puts("ERROR: Processed #{stats.enqueued_jobs} venues when limit was 15!")
    end

  {:error, reason} ->
    IO.puts("❌ GeeksWhoDrinkIndexJob failed: #{inspect(reason)}")
    IO.puts("\n========== FAIL ==========")
    IO.puts("Job failed: #{inspect(reason)}")
end

# Don't wait for any scheduled jobs to execute
IO.puts("\n🛑 Test complete. Not waiting for scheduled jobs to execute.")

# Don't exit - we want to see details of the jobs that were scheduled
# but we also don't want to wait for them to complete
IO.puts("\nJobs are now scheduled but we're not going to wait for them.")
IO.puts("Press Ctrl+C or wait for script to finish if you want to see some job results.")

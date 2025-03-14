# Test script for GeeksWhoDrinkIndexJob
# Run with: mix run lib/debug/test_geeks_who_drink.exs

require Logger
alias TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob
alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.NonceExtractor

# Configure logger to show info level and above
Logger.configure(level: :info)
Logger.info("""

====== TEST GEEKS WHO DRINK INDEX JOB ======
🧪 Starting test with limit of 3 venues ONLY
============================================
""")

# Clear any existing jobs
{:ok, _} = TriviaAdvisor.Repo.query("DELETE FROM oban_jobs")
Logger.info("✅ Cleared existing jobs")

# Test direct fetching of venues to examine the data
Logger.info("\n📝 Testing venue fetching...")

# Get nonce first and then fetch venues
{:ok, nonce} = NonceExtractor.fetch_nonce()
{:ok, venues} = GeeksWhoDrinkIndexJob.fetch_venues(nonce)

# Examine first 3 venues' data
venues_to_examine = Enum.take(venues, 3)

# Print venue data to debug source_url issue
Enum.each(venues_to_examine, fn venue ->
  Logger.info("Venue data: #{inspect(venue, pretty: true)}")
  Logger.info("---")
end)

# Record start time
start_time = :os.system_time(:millisecond)

# Create a mock job with limit 3 (smaller for easier debugging)
Logger.info("\n📝 DIRECT METHOD: Running GeeksWhoDrinkIndexJob.perform with limit=3...\n")

# Create a properly structured Oban.Job struct that matches the pattern in perform
job = %Oban.Job{
  id: 999999,
  args: %{"limit" => 3}
}

# Run the job
result = GeeksWhoDrinkIndexJob.perform(job)

# Record end time and calculate duration
end_time = :os.system_time(:millisecond)
duration = (end_time - start_time) / 1000

# Report the results
case result do
  {:ok, stats} ->
    Logger.info("✅ Job completed successfully in #{duration} seconds!")
    Logger.info("📊 Stats: #{inspect(stats)}")

    if stats.enqueued_jobs <= 3 do
      Logger.info("\n========== PASS ==========")
      Logger.info("Successfully processed venues with limit of 3")
      Logger.info("Venues processed: #{stats.enqueued_jobs}")
      Logger.info("Venues skipped: #{stats.skipped_venues}")
    else
      Logger.info("\n========== FAIL ==========")
      Logger.info("ERROR: Processed #{stats.enqueued_jobs} venues when limit was 3!")
    end

  {:error, error} ->
    Logger.error("❌ Job failed with error: #{inspect(error)}")
end

Logger.info("\n�� Test complete.")

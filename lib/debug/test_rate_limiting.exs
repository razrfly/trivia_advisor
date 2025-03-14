# Test script for hourly rate limiting
# Run with: mix run lib/debug/test_rate_limiting.exs

require Logger
alias TriviaAdvisor.Scraping.RateLimiter
alias TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkDetailJob

# Configure logger to show info level and above
Logger.configure(level: :info)
Logger.info("""

====== TEST HOURLY RATE LIMITING ======
🧪 Testing hourly capped job scheduling
======================================
""")

# Clear any existing jobs first
{:ok, _} = TriviaAdvisor.Repo.query("DELETE FROM oban_jobs")
Logger.info("✅ Cleared existing jobs")

# Create a list of test items (we'll use simple maps)
test_count = 125  # Create more than max_per_hour to test distribution
test_items = Enum.map(1..test_count, fn i -> %{id: i, name: "Test Item #{i}"} end)

Logger.info("📝 Testing with #{test_count} items")
Logger.info("🔢 Max jobs per hour: #{RateLimiter.max_jobs_per_hour()}")

# Record start time
start_time = :os.system_time(:millisecond)

# Schedule jobs with the new hourly capped function
scheduled_count = RateLimiter.schedule_hourly_capped_jobs(
  test_items,
  GeeksWhoDrinkDetailJob,
  fn item -> %{test_item: item} end
)

# Record end time and calculate duration
end_time = :os.system_time(:millisecond)
duration = (end_time - start_time) / 1000

Logger.info("✅ Scheduled #{scheduled_count} jobs in #{duration} seconds")

# Verify job distribution by hour
{:ok, result} = TriviaAdvisor.Repo.query("""
  SELECT
    EXTRACT(HOUR FROM scheduled_at) AS hour,
    COUNT(*) AS job_count
  FROM
    oban_jobs
  GROUP BY
    EXTRACT(HOUR FROM scheduled_at)
  ORDER BY
    hour
""")

# Print distribution results
hours = result.rows
Logger.info("\n📊 Job Distribution By Hour:")

Enum.each(hours, fn [hour, count] ->
  # Convert Decimal to integer using Decimal.to_integer/1 or String-based approach
  hour_int = if is_binary(hour), do: String.to_integer(hour), else: Decimal.to_integer(hour)
  Logger.info("Hour #{hour_int}: #{count} jobs")
end)

# Calculate hours needed for processing
max_per_hour = RateLimiter.max_jobs_per_hour()
hours_needed = ceil(test_count / max_per_hour)

# Final success/failure check
if length(hours) >= hours_needed do
  Logger.info("\n========== PASS ==========")
  Logger.info("Successfully distributed #{test_count} jobs across #{length(hours)} hours")
  Logger.info("(Expected minimum: #{hours_needed} hours)")
else
  Logger.info("\n========== FAIL ==========")
  Logger.info("ERROR: Jobs not distributed correctly")
  Logger.info("Expected at least #{hours_needed} hours, got #{length(hours)}")
end

Logger.info("\n🧪 Test complete.")

# Count total jobs to double-check
{:ok, %{rows: [[total_jobs]]}} = TriviaAdvisor.Repo.query("SELECT COUNT(*) FROM oban_jobs")
Logger.info("Total scheduled jobs in database: #{total_jobs}")

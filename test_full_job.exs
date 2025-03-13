require Logger
alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo

Logger.info("🚀 Running full job verification test...")

# Get the Inquizition source
source = Repo.get_by!(Source, name: "inquizition")
Logger.info("📊 Found source: #{inspect(source)}")

# Run the job
Logger.info("🔄 Running job...")
{time, {:ok, result}} = :timer.tc(fn ->
  InquizitionIndexJob.perform(%Oban.Job{args: %{}, id: 999999})
end)

# Log results
Logger.info("⏱️ Job completed in #{time / 1_000_000} seconds")
Logger.info("📈 Job result: #{inspect(result)}")

# Specifically verify the number of venues processed
Logger.info("🧮 Venues processed: #{result.enqueued_jobs}")
Logger.info("🧮 Venues skipped: #{result.skipped_venues}")
Logger.info("🧮 Total venues: #{result.venue_count}")

# Print conclusion
if result.enqueued_jobs == 0 do
  Logger.info("✅ TEST PASSED: No venues were processed!")
else
  Logger.error("❌ TEST FAILED: #{result.enqueued_jobs} venues were processed!")
end

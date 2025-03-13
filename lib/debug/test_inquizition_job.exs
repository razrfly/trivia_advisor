# This script tests the InquizitionIndexJob with a limit of 1 venue
# Run with: mix run test_inquizition_job.exs

# Start any necessary applications
Application.ensure_all_started(:trivia_advisor)

# Set a limit for testing
limit = 1
IO.puts("🧪 Running Inquizition Index Job TEST with limit of #{limit} venues...")

# Call the index job with the limit
case TriviaAdvisor.Scraping.Oban.InquizitionIndexJob.perform(%Oban.Job{args: %{"limit" => limit}}) do
  {:ok, result} ->
    IO.puts("\n✅ Test completed successfully!")
    IO.puts("📊 Found #{result.venue_count} venues total")
    IO.puts("📊 Enqueued #{result.enqueued_jobs} detail jobs (limited to #{limit})")

  other ->
    IO.puts("\n❌ Test failed: #{inspect(other)}")
    System.halt(1)
end

# Add a delay to ensure logs are printed before exiting
:timer.sleep(1000)

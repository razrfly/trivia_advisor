# Script to run the timestamp update test for Inquizition scraper
Logger.configure(level: :info)
IO.puts("Starting timestamp update test for Inquizition scraper")

# Run the test with "The One Tun" venue and source_id 3 (Inquizition)
result = TriviaAdvisor.Scraping.TimestampTest.run_timestamp_test("The One Tun", 3)

# Output the result
case result do
  {:ok, _data} ->
    IO.puts("\n✅ TEST PASSED: All event source timestamps were properly updated")
    System.stop(0)

  {:error, :venue_not_found} ->
    IO.puts("\n❌ TEST FAILED: Venue 'The One Tun' not found")
    System.stop(1)

  {:error, :no_event_sources} ->
    IO.puts("\n❌ TEST FAILED: No event sources found for venue")
    System.stop(1)

  {:error, _data} ->
    IO.puts("\n❌ TEST FAILED: Some event source timestamps were not updated")
    System.stop(1)
end

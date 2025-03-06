# Run with: mix run lib/scripts/test_google_lookup_job.exs

# Import required modules
alias TriviaAdvisor.Scraping.Oban.GoogleLookupJob
alias Oban.Job

# Define a test venue
venue = %{
  "venue_name" => "House of Hammerton, Islington",
  "address" => "99 Holloway Road, England N7 8LT, United Kingdom",
  "phone" => "020 7607 2634",
  "website" => "https://www.hammertonbrewery.co.uk/site/house-of-hammerton/",
  "facebook" => nil,
  "instagram" => nil,
  "existing_venue_id" => nil
}

IO.puts("Testing GoogleLookupJob with venue:")
IO.inspect(venue)

# Create a fake Oban job
job = %Job{
  id: 0,
  args: venue,
  queue: "google_api",
  worker: GoogleLookupJob
}

# Run the job synchronously
IO.puts("\nRunning GoogleLookupJob...")
case GoogleLookupJob.perform(job) do
  {:ok, result} ->
    IO.puts("\n✅ Job succeeded!")
    IO.inspect(result, label: "Result")

  {:error, error} ->
    IO.puts("\n❌ Job failed!")
    IO.inspect(error, label: "Error")

  other ->
    IO.puts("\n⚠️ Unexpected response:")
    IO.inspect(other)
end

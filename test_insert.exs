# This script directly tests the job insertion part that's failing
# Run with: mix run test_insert.exs

# Start any necessary applications
Application.ensure_all_started(:trivia_advisor)
Application.ensure_all_started(:oban)

alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Scraping.Source

# Get the source
source = Repo.get_by!(Source, name: "inquizition")
source_id = source.id

# Create test venue data
venue_data = %{
  "name" => "Test Venue",
  "address" => "123 Test Street, London",
  "phone" => "123-456-7890",
  "website" => "https://example.com",
  "source_id" => source_id,
  "time_text" => "Every Friday at 8pm"
}

IO.puts("🧪 Testing direct job creation and insertion...")

# Create the job - this returns a changeset, not an {:ok, job} tuple
job_result = InquizitionDetailJob.new(%{
  "venue_data" => venue_data
})

IO.puts("Job creation result type: #{inspect(job_result.__struct__)}")

# Handle all possible job creation results
job = case job_result do
  {:ok, job} ->
    IO.puts("Got {:ok, job} tuple")
    job
  %Ecto.Changeset{valid?: true} = changeset ->
    IO.puts("Got valid changeset")
    changeset
  other ->
    IO.puts("Got unexpected result: #{inspect(other)}")
    nil
end

# Try to insert the job if we got a valid job or changeset
if job do
  IO.puts("Attempting to insert job...")

  # Insert the job
  case Oban.insert(job) do
    {:ok, inserted_job} ->
      IO.puts("✅ Success! Job inserted with ID: #{inserted_job.id}")

    {:error, error} ->
      IO.puts("❌ Error inserting job: #{inspect(error)}")

    other ->
      IO.puts("❌ Unexpected result: #{inspect(other)}")
  end
else
  IO.puts("❌ No valid job to insert")
end

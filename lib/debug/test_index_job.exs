# Test QuizmeistersIndexJob with force_refresh_images=true

require Logger
alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Scraping.Source

IO.puts("\n===== TESTING QUIZMEISTERS INDEX JOB WITH FORCE_REFRESH_IMAGES=TRUE =====")

# Get the Quizmeisters source
source = Repo.get_by(Source, name: "quizmeisters")
if is_nil(source) do
  IO.puts("ERROR: Source 'quizmeisters' not found")
  System.halt(1)
end

IO.puts("Found source: #{source.name} (id: #{source.id})")

# Create job arguments with force_refresh_images=true
args = %{
  "force_refresh_images" => true,
  "force_update" => true,
  "limit" => 1  # Only process 1 venue for testing
}

# Create job struct
job = %Oban.Job{
  id: 999998,  # Use a different ID than previous tests
  queue: "test_queue",
  worker: "TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob",
  args: args,
  state: "available",
  inserted_at: DateTime.utc_now(),
  scheduled_at: DateTime.utc_now(),
  attempted_at: nil,
  completed_at: nil,
  attempted_by: nil,
  discarded_at: nil,
  priority: 0,
  tags: ["test"],
  errors: [],
  max_attempts: 3
}

IO.puts("\nRunning INDEX job with args: #{inspect(args)}")

# Run the index job directly
result = QuizmeistersIndexJob.perform(job)

IO.puts("\n===== INDEX JOB COMPLETED =====")
IO.puts("Result: #{inspect(result)}")
IO.puts("")
IO.puts("Now check the application logs to see if a detail job was scheduled")
IO.puts("with force_refresh_images=true")
IO.puts("")
IO.puts("The detail job should have been scheduled to run shortly after this job completes.")

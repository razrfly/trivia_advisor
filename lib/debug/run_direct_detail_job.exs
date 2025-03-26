# Run a QuizmeistersDetailJob directly with force_refresh_images=true

require Logger
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Scraping.Source

IO.puts("\n===== RUNNING QUIZMEISTERS DETAIL JOB DIRECTLY =====")
IO.puts("This will run with force_refresh_images=true to verify the fix\n")

# Get source
source = Repo.get_by(Source, name: "quizmeisters")
if is_nil(source) do
  IO.puts("ERROR: Source 'quizmeisters' not found")
  System.halt(1)
end

# Create sample venue data
venue_data = %{
  "name" => "10 Toes Buderim",
  "phone" => "07 5373 5003",
  "address" => "15/3 Pittards Rd, Buderim, Queensland, 4556, AU",
  "url" => "https://www.quizmeisters.com/venues/qld-10-toes",
  "postcode" => "4556",
  "latitude" => "-26.6630807",
  "longitude" => "153.0518295"
}

# Create job arguments with force_refresh_images=true
args = %{
  "venue" => venue_data,
  "source_id" => source.id,
  "force_refresh_images" => true,
  "force_update" => true
}

# Create job struct
job = %Oban.Job{
  id: 999997,  # Different ID from previous tests
  queue: "test_queue",
  worker: "TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob",
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

IO.puts("Running with args: #{inspect(args)}")

# Configure logging to make it easier to see force_refresh logs
Logger.configure(level: :info)

IO.puts("\n⏱️ Running job (will take ~30 seconds)...")

# Define a pattern we'll search for to verify the fix
verification_pattern = "force_refresh=true"
found_true_logs = false

# Set up a custom logger handler to look for the pattern
defmodule VerificationLogger do
  def init(_) do
    # Track whether we found force_refresh=true logs
    # Store in process dictionary for simplicity
    Process.put(:found_true_logs, false)
    {:ok, %{}}
  end

  def handle_event({_level, _gl, {Logger, message, _ts, _md}}, state) do
    message_str = IO.chardata_to_string(message)

    # Check for force_refresh=true in logs
    if String.contains?(message_str, ["force_refresh=true", "force_refresh: true"]) do
      # Found a true log, update our tracking
      Process.put(:found_true_logs, true)

      # Highlight these logs
      IO.puts("\n✅ FOUND: #{message_str}")
    end

    {:ok, state}
  end
end

# Add our verification logger
:logger.add_handler(:verification_logger, VerificationLogger, %{})

# Run the job
result = QuizmeistersDetailJob.perform(job)

# Remove our verification logger
:logger.remove_handler(:verification_logger)

# Check if we found the pattern
found_true_logs = Process.get(:found_true_logs, false)

IO.puts("\n===== JOB COMPLETED =====")
IO.puts("Result: #{inspect(result)}")

# Show verification results
IO.puts("\n===== VERIFICATION RESULTS =====")
if found_true_logs do
  IO.puts("✅ SUCCESS: Found force_refresh=true in the logs!")
  IO.puts("The fix is working correctly!")
else
  IO.puts("❌ FAILURE: Could not find force_refresh=true in the logs")
  IO.puts("The fix is not working correctly.")
end

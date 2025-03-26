# Real job test with force_refresh_images=true
# This runs a real QuizmeistersDetailJob directly to verify our fix

# Required modules
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Scraping.Source
require Logger

# Configure logging to focus on what we need
Logger.configure(level: :info)

# Keep track of force refresh values
force_refresh_values = []

# Function to track log messages related to force_refresh
defmodule ForceRefreshTracker do
  def track_log(message) do
    cond do
      String.contains?(message, "force_refresh=true") -> :true
      String.contains?(message, "force_refresh_images = true") -> :true
      String.contains?(message, "force_refresh: true") -> :true
      String.contains?(message, "force_refresh=false") -> :false
      String.contains?(message, "force_refresh_images = false") -> :false
      String.contains?(message, "force_refresh: false") -> :false
      true -> nil
    end
  end
end

IO.puts("\n===== TESTING REAL JOB WITH FORCE_REFRESH_IMAGES=TRUE =====")

# Get source ID for quizmeisters (lowercase)
source = Repo.get_by(Source, name: "quizmeisters")
if is_nil(source) do
  IO.puts("❌ ERROR: Could not find quizmeisters source")
  System.halt(1)
end

# Create venue data for test
venue_data = %{
  "name" => "10 Toes Buderim",
  "phone" => "07 5373 5003",
  "address" => "15/3 Pittards Rd, Buderim, Queensland, 4556, AU",
  "url" => "https://www.quizmeisters.com/venues/qld-10-toes",
  "postcode" => "4556",
  "latitude" => "-26.6630807",
  "longitude" => "153.0518295"
}

args = %{
  "venue" => venue_data,
  "source_id" => source.id,
  "force_refresh_images" => true # This is what we're testing
}

# Create job struct
job = %Oban.Job{
  id: 999999,
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

# Running the job
IO.puts("\n➡️ Running QuizmeistersDetailJob with force_refresh_images=true")
IO.puts("⏱️  This will take about 20-30 seconds...\n")

result = QuizmeistersDetailJob.perform(job)

IO.puts("\n===== JOB COMPLETED =====")
IO.puts("Result: #{inspect(result)}")

IO.puts("\nCheck the logs above for these messages:")
IO.puts("1. 'Process dictionary force_refresh_images set to: true'")
IO.puts("2. 'Process dictionary force_refresh_images value: true'")
IO.puts("3. 'TASK is using force_refresh=true from captured variable'")
IO.puts("4. 'HERO IMAGE TASK using force_refresh=true'")
IO.puts("5. Any logs with 'force_refresh: true' for image downloading")

IO.puts("\nIf these show TRUE instead of FALSE, our fix worked.")

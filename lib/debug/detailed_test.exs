# Detailed test for force_refresh_images flag propagation
# This script traces the flag throughout the system to identify where it's being lost

alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Events.EventStore
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Scraping.Source
require Logger

# Configure logging to focus on what we need
Logger.configure(level: :info)

IO.puts("\n===== ANALYZING FORCE_REFRESH_IMAGES FLAG THROUGHOUT THE SYSTEM =====")

# Part 1: Verify the original issue directly - force_refresh_images=true in Process dictionary is lost when creating Tasks
IO.puts("\n--- PART 1: PROCESS DICTIONARY ISOLATION TEST ---")
IO.puts("Setting force_refresh_images=true in the process dictionary")

# Set the flag to true
Process.put(:force_refresh_images, true)
IO.puts("Main process: force_refresh_images = #{inspect(Process.get(:force_refresh_images))}")

# Create a task to verify the flag isn't passed
task = Task.async(fn ->
  value = Process.get(:force_refresh_images)
  Process.put(:temp_result, value)
  IO.puts("Task process: force_refresh_images = #{inspect(value)}")
end)
Task.await(task)

IO.puts("\nCONCLUSION PART 1: Process dictionary values do NOT transfer to tasks/separate processes")
IO.puts("This confirms the core issue - we must explicitly capture and pass the value to each Task\n")

# Part 2: Test QuizmeistersDetailJob to ensure our fixes propagate the value correctly
IO.puts("\n--- PART 2: SYSTEM-WIDE TEST WITH REWRITTEN JOB IMPLEMENTATION ---")

# Get the source
source = Repo.get_by(Source, name: "quizmeisters")
if is_nil(source) do
  IO.puts("ERROR: Source 'quizmeisters' not found")
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

IO.puts("\n➡️ Creating job with force_refresh_images=true")
args = %{
  "venue" => venue_data,
  "source_id" => source.id,
  "force_refresh_images" => true
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

# Set up a temporary logger backend to capture force_refresh related logs
defmodule ForceRefreshLogger do
  require Logger

  def start do
    # Configure to capture everything
    :ok = :logger.add_handler(
      :force_refresh_tracker,
      :logger_std_h,
      %{
        level: :info,
        filter_default: :log,
        config: %{type: :standard_io},
        formatter: {__MODULE__, :format}
      }
    )
  end

  def format(level, message, _timestamp, _metadata) do
    if String.contains?(to_string(message), ["force_refresh", "TASK is using", "HERO IMAGE TASK"]) do
      msg = to_string(message)
      color = cond do
        String.contains?(msg, "=true") || String.contains?(msg, "= true") -> "\e[32m" # green
        String.contains?(msg, "=false") || String.contains?(msg, "= false") -> "\e[31m" # red
        true -> "\e[0m" # default
      end
      reset = "\e[0m"
      "#{color}#{msg}#{reset}\n"
    else
      # Don't log other messages through this formatter
      ""
    end
  end

  def stop do
    :ok = :logger.remove_handler(:force_refresh_tracker)
  end
end

# Start the custom logger
ForceRefreshLogger.start()

IO.puts("\n⏱️  Running job (will take ~30 seconds)...")
IO.puts("🔍 WATCH FOR force_refresh VALUES in the colored logs below!\n")

result = QuizmeistersDetailJob.perform(job)

# Stop the custom logger
ForceRefreshLogger.stop()

IO.puts("\n===== JOB COMPLETED =====")
IO.puts("Result: #{inspect(result)}")

IO.puts("\n===== CONCLUSION =====")
IO.puts("If you saw any force_refresh=false or force_refresh_images = false in the logs")
IO.puts("above, then our fix isn't complete.")
IO.puts("")
IO.puts("If ALL force_refresh values were TRUE, then our fix succeeded.")
IO.puts("")
IO.puts("Look specifically for:")
IO.puts("1. Process dictionary force_refresh_images value: true or false")
IO.puts("2. TASK is using force_refresh=true or false from captured variable")
IO.puts("3. HERO IMAGE TASK using force_refresh=true or false")
IO.puts("4. force_refresh: true or false in image downloading")

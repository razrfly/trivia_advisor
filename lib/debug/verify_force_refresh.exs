# Script to verify that force_refresh_images flag is correctly propagated
# in QuizmeistersDetailJob

alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Scraping.Source
require Logger

# Set logging level to info to see all logs
Logger.configure(level: :info)

IO.puts("\n\n===== VERIFICATION TEST FOR FORCE_REFRESH FIX =====\n")

# Get the last detail job that was run
source = Repo.get_by(Source, name: "Quizmeisters")
source_id = source.id

# Create job args with force_refresh_images=true
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
  "source_id" => source_id,
  "force_refresh_images" => true
}

IO.puts("Creating test job with these arguments:")
IO.inspect(args, pretty: true)

# Create a job struct directly - remove fields that aren't in the struct
job = %Oban.Job{
  id: 999999, # Use a high ID to avoid conflicts
  queue: "test_queue",
  worker: "TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob",
  args: args,
  state: "available",
  attempted_at: nil,
  completed_at: nil,
  attempted_by: nil,
  discarded_at: nil,
  priority: 0,
  tags: ["test"],
  errors: [],
  inserted_at: DateTime.utc_now(),
  scheduled_at: DateTime.utc_now(),
  max_attempts: 3
}

IO.puts("\n===== Running job with force_refresh_images=true =====\n")

# Execute the job directly
result = QuizmeistersDetailJob.perform(job)

IO.puts("\n===== Job Execution Complete =====")
IO.puts("Result: #{inspect(result)}")
IO.puts("\n===== VERIFICATION COMPLETED =====")
IO.puts("Check the logs for references to force_refresh_images")
IO.puts("Verify that the following statements appeared:")
IO.puts("- Process dictionary force_refresh_images set to: true")
IO.puts("- Using force_refresh=true for performer image")
IO.puts("- TASK is using force_refresh=true from captured variable")
IO.puts("- force_refresh: true in the image download logs")
IO.puts("If these appear, the fix is successful.")

# Final verification script that directly demonstrates the bug
# This sets up logging with a direct test that clearly shows true->false conversion

defmodule VerificationTest do
  require Logger
  alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

  def run do
    IO.puts("\n===== DIRECT VERIFY: force_refresh_images TRUE -> FALSE bug =====")

    # Configure logger to be as verbose as possible
    Logger.configure(level: :debug)

    # Create example venue data similar to what the job would process
    venue_data = %{
      "name" => "10 Toes Buderim",
      "phone" => "07 5373 5003",
      "address" => "15/3 Pittards Rd, Buderim, Queensland, 4556, AU",
      "url" => "https://www.quizmeisters.com/venues/qld-10-toes",
      "postcode" => "4556",
      "latitude" => "-26.6630807",
      "longitude" => "153.0518295"
    }

    # Get the source_id for Quizmeisters
    source = TriviaAdvisor.Repo.get_by(TriviaAdvisor.Scraping.Source, name: "Quizmeisters")
    source_id = source.id

    # Create job args - explicitly setting force_refresh_images to TRUE
    args = %{
      "venue" => venue_data,
      "source_id" => source_id,
      "force_refresh_images" => true  # THIS SHOULD BE PROPAGATED TO ALL IMAGE OPERATIONS
    }

    # Turn these args into a job struct
    job = %Oban.Job{
      id: 999999,
      queue: "test",
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

    IO.puts("\n➡️ Starting test with force_refresh_images = TRUE in job args")
    IO.puts("⚠️ WATCH FOR force_refresh values in the logs")

    # Process the job directly
    result = QuizmeistersDetailJob.perform(job)

    # Show the result
    IO.puts("\n✅ Job completed with result: #{inspect(result)}")

    IO.puts("\n===== BUG VERIFICATION =====")
    IO.puts("If you saw:")
    IO.puts("1. 'Process dictionary force_refresh_images set to: true'")
    IO.puts("2. 'Process dictionary force_refresh_images for hero image: false'")
    IO.puts("3. 'HERO IMAGE TASK using force_refresh=false'")
    IO.puts("")
    IO.puts("It proves the bug: force_refresh_images=true is correctly")
    IO.puts("set at job start but becomes false for hero image processing.")
  end
end

# Run the test
VerificationTest.run()

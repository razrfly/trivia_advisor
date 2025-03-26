# Script to specifically track force_refresh flag in logs
# This script will run a job with force_refresh_images=true and verify if logs show true or false

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
require Logger

# First let's test by directly running the job with force_refresh_images=true
IO.puts("\n\n===== TRACKING FORCE_REFRESH VALUES IN LOGS =====\n")
IO.puts("This test specifically checks if force_refresh is correctly propagated to image downloaders")
IO.puts("We'll run a job with force_refresh_images=true and check the logs")

IO.puts("\n--- Creating job with force_refresh_images=true ---")
args = %{
  "force_update" => true,
  "force_refresh_images" => true,
  "limit" => 1, # Process just one venue for quicker testing
  "test_mode" => true
}

# Insert the job
{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(args))
IO.puts("Job inserted with ID: #{job.id}")

# Tell the user what to look for in the logs
IO.puts("\n===== WATCH THE FOLLOWING LOG MESSAGES =====")
IO.puts("1. You should see: 'Process dictionary force_refresh_images set to: true'")
IO.puts("2. You should see: 'Process dictionary force_refresh_images value: true'")
IO.puts("3. You should see: 'TASK is using force_refresh=true from captured variable'")
IO.puts("4. You should see: 'HERO IMAGE TASK using force_refresh=true'")
IO.puts("5. You should see: 'force_refresh: true' in the image download logs")
IO.puts("\nSpecifically, look for these logs. If you see 'false' instead of 'true', the fix isn't working.")

# Wait for user to read the instructions
IO.puts("\nWaiting 5 seconds for the job to start running...")
Process.sleep(5_000)

# Add some space before concluding
IO.puts("\n\n--- Continuing after job launch ---")
IO.puts("Check your console for the logs mentioned above.")
IO.puts("The job is running in the background. You can view the logs in your terminal output.")

IO.puts("\n===== VERIFICATION CHECKLIST =====")
IO.puts("Look for these specific logs in your console output:")
IO.puts("✓ Process dictionary force_refresh_images set to: true")
IO.puts("✓ Process dictionary force_refresh_images value: true")
IO.puts("✓ TASK is using force_refresh=true from captured variable")
IO.puts("✓ HERO IMAGE TASK using force_refresh=true")
IO.puts("✓ force_refresh: true in the image download logs")

IO.puts("\nIf all logs show TRUE instead of FALSE, the fix is working correctly.")

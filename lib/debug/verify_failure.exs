# Simple script to demonstrate the force_refresh_images flag not working as expected.
# This script runs a job with force_refresh_images=true and checks the console output to
# see if the flag is properly propagated to the hero image download code.

# Import the job module we'll test
alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob

IO.puts("\n===== TESTING IF FORCE_REFRESH_IMAGES=TRUE WORKS =====")
IO.puts("This will run a job with force_refresh_images=true and examine the output")

# Increase log level to info to ensure we see the relevant messages
Logger.configure(level: :debug)

# Create and insert a job with force_refresh_images explicitly set to true
args = %{
  "force_refresh_images" => true,  # This should be propagated to all image downloads
  "force_update" => true,
  "limit" => 1                     # Process just one venue for quicker testing
}

IO.puts("\nCreating job with:")
IO.puts("  force_refresh_images: #{inspect(args["force_refresh_images"])}")
IO.puts("  force_update: #{inspect(args["force_update"])}")
IO.puts("  limit: #{inspect(args["limit"])}")

# Insert the job
{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(args))
IO.puts("Job created with ID: #{job.id}")

# Wait a moment to let the job start
IO.puts("\nWaiting 7 seconds for job to run...")
Process.sleep(7_000)

IO.puts("\n===== VERIFICATION INSTRUCTIONS =====")
IO.puts("WATCH THE LOGS ABOVE ☝️ and check:")
IO.puts("")
IO.puts("1. You should see: 'Process dictionary force_refresh_images set to: true'")
IO.puts("2. But then you'll see: 'Process dictionary force_refresh_images for hero image: false'")
IO.puts("3. And: 'HERO IMAGE TASK using force_refresh=false'")
IO.puts("4. And: 'Processing event hero image URL: ... force_refresh: false'")
IO.puts("")
IO.puts("THIS DEMONSTRATES THE BUG: force_refresh_images=true is set correctly in the")
IO.puts("process dictionary at job start, but by the time we get to hero image processing,")
IO.puts("it's somehow becoming false.")
IO.puts("")
IO.puts("===== LOOK FOR THESE EXACT LINES IN THE LOGS ABOVE =====")
IO.puts("⚠️ Process dictionary force_refresh_images for hero image: false")
IO.puts("🖼️ Processing hero image (normal mode): https://cdn......")
IO.puts("🔍 Hero image force_refresh_images = false")
IO.puts("⚠️ HERO IMAGE TASK using force_refresh=false")
IO.puts("📸 Processing event hero image URL: ... force_refresh: false")

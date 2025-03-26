# Direct test for force_refresh_images flag propagation issue
# This script creates a simple test case that demonstrates how force_refresh_images=true
# becomes false during hero image processing

# Import required modules
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

IO.puts("\n===== TESTING FORCE_REFRESH_IMAGES PROPAGATION =====")

# Part 1: Set up process dictionary with force_refresh_images=true
Process.put(:force_refresh_images, true)
IO.puts("Process dictionary now has force_refresh_images = #{inspect(Process.get(:force_refresh_images))}")

# Part 2: Call process_hero_image indirectly through a mock function that simulates it
# This shows what happens inside that function without needing to run a full job
mock_hero_image_fn = fn ->
  # These exact lines come from process_hero_image function
  force_refresh_images = Process.get(:force_refresh_images, false)

  IO.puts("\n⬇️ Simulating process_hero_image function...")
  IO.puts("⚠️ Process dictionary force_refresh_images value inside function: #{inspect(force_refresh_images)}")

  # Log what would happen next with this value
  if force_refresh_images do
    IO.puts("➡️ Would process hero image with FORCE REFRESH ENABLED")
  else
    IO.puts("➡️ Would process hero image in NORMAL mode (NO force refresh)")
  end
end

# Run the mock function
mock_hero_image_fn.()

# Part 3: Try retrieving the process dictionary value directly in a Task, which is how
# the real function calls ImageDownloader
IO.puts("\n⬇️ Testing Task process isolation (root cause of bug)...")

task = Task.async(fn ->
  # Get the value from process dictionary inside the Task
  task_value = Process.get(:force_refresh_images)
  IO.puts("⚠️ Process dictionary value inside Task: #{inspect(task_value)}")

  if is_nil(task_value) do
    IO.puts("❌ BUG CONFIRMED: Process dictionary values DO NOT transfer to Task processes")
    IO.puts("This explains why force_refresh_images=true becomes false during image processing")
  else
    IO.puts("Unexpected: Value transferred to task")
  end
end)

Task.await(task)

IO.puts("\n===== CONCLUSION =====")
IO.puts("The issue occurs because:")
IO.puts("1. force_refresh_images=true is correctly set in the main process")
IO.puts("2. Tasks are created for image processing (hero_image, performer_image)")
IO.puts("3. Tasks run in their own processes with SEPARATE process dictionaries")
IO.puts("4. Process dictionary values DO NOT transfer to Task processes")
IO.puts("5. When tasks check Process.get(:force_refresh_images, false), they get false")
IO.puts("\nThis is why force_refresh_images=true becomes false during image processing")
IO.puts("To fix: need to explicitly pass or capture the value before Task creation")

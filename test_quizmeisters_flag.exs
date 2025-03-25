#!/usr/bin/env elixir

# Direct test script for QuizmeistersIndexJob force_refresh_images propagation
# Run with: mix run test_quizmeisters_flag.exs

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
require Logger

# Set log level to debug to see all messages
Logger.configure(level: :debug)

# Create the index job with force_refresh_images=true and limit=1
force_refresh = true
IO.puts("\n=== CREATING INDEX JOB with force_refresh_images=#{force_refresh} ===")

job_args = %{
  "force_refresh_images" => force_refresh,
  "force_update" => true,
  "limit" => 1
}

{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(job_args))
IO.puts("Created job #{job.id} with args: #{inspect(job.args)}")

# Add patching for QuizmeistersDetailJob to capture what args it receives
old_detail_perform = Function.capture(TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob, :perform, 1)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  def perform(%Oban.Job{id: job_id, args: args} = job) do
    # Log the received args
    IO.puts("\n=== DETAIL JOB #{job_id} RECEIVED ARGS: ===")
    IO.inspect(args, pretty: true)
    
    # Check specifically for force_refresh_images
    force_refresh_images = Map.get(args, "force_refresh_images", false)
    IO.puts("\n*** FORCE REFRESH IMAGES FLAG VALUE: #{inspect(force_refresh_images)} ***")
    
    # Call the original function to continue processing
    unquote(old_detail_perform).(job)
  end
end

# Add patching for ImageDownloader to capture if force_refresh is true when downloading
old_download_image = Function.capture(TriviaAdvisor.Scraping.Helpers.ImageDownloader, :download_image, 3)

defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  def download_image(url, prefix, force_refresh) do
    # Log the force_refresh value
    IO.puts("\n=== IMAGE DOWNLOAD REQUESTED with force_refresh=#{inspect(force_refresh)} ===")
    IO.puts("URL: #{url}")
    
    # Call the original function
    unquote(old_download_image).(url, prefix, force_refresh)
  end
end

IO.puts("\n=== EXECUTING JOB DIRECTLY ===")
IO.puts("This will run the QuizmeistersIndexJob and create a QuizmeistersDetailJob")
IO.puts("Look for 'FORCE REFRESH IMAGES FLAG VALUE:' in the output to see if true/false")

# Execute the job directly
Oban.Job.execute(job)

IO.puts("\n=== TEST COMPLETED ===")
IO.puts("If the flag value was 'false', the fix is NOT working yet. Modify the code and run this script again.")
IO.puts("If the flag value was 'true', the fix IS working!")
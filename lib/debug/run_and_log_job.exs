#!/usr/bin/env elixir

# This script runs a QuizmeistersIndexJob with force_refresh_images=true and logs the output
# The goal is to confirm whether force_refresh_images=true in args becomes force_refresh=false in logs

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
require Logger

# Set logging level to info to see all relevant logs
Logger.configure(level: :debug)

IO.puts("\n\n========= RUNNING TEST JOB WITH FORCE_REFRESH_IMAGES=TRUE =========\n")

# Create and insert the job
job_args = %{"force_refresh_images" => true, "force_update" => true, "limit" => 1}
IO.puts("Job args: #{inspect(job_args)}")

{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(job_args))
IO.puts("Job inserted with ID: #{job.id}")

# Wait a moment for the job to be processed and logs to appear
IO.puts("\nWaiting for job processing...")
:timer.sleep(10_000)

IO.puts("\n========= JOB COMPLETED =========")
IO.puts("Check the logs above for 'force_refresh: false' messages despite 'force_refresh_images: true' in the arguments.")

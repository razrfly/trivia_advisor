#!/usr/bin/env elixir

# This script adds tracing to key functions to track the force_refresh flag
# Specifically, it will show if force_refresh_images=true in args becomes force_refresh=false in logs

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
alias TriviaAdvisor.Events.EventStore
require Logger

# Set logging level to info to see all relevant logs
Logger.configure(level: :info)

IO.puts("\n\n========= TRACING FORCE_REFRESH_IMAGES FLAG =========\n")

# ===== Patch the ImageDownloader.download_event_hero_image function to trace force_refresh =====
old_download_event_hero_image = Function.capture(TriviaAdvisor.Scraping.Helpers.ImageDownloader, :download_event_hero_image, 2)

defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  def download_event_hero_image(url, force_refresh) do
    # Log the actual force_refresh value received
    IO.puts("[TRACER] ImageDownloader.download_event_hero_image called with force_refresh=#{inspect(force_refresh)}")

    # Call the original function
    unquote(old_download_event_hero_image).(url, force_refresh)
  end
end

# ===== Patch EventStore.download_hero_image to trace force_refresh =====
old_download_hero_image = Function.capture(TriviaAdvisor.Events.EventStore, :download_hero_image, 1)

defmodule TriviaAdvisor.Events.EventStore do
  defp download_hero_image(url) do
    # Get force_refresh_images from process dictionary
    force_refresh_images = Process.get(:force_refresh_images, false)

    # Log what we got from the process dictionary
    IO.puts("[TRACER] EventStore.download_hero_image using force_refresh_images=#{inspect(force_refresh_images)} from process dictionary")

    # Check if download_hero_image is hardcoding force_refresh_images
    raw_func = :erlang.fun_to_string(unquote(old_download_hero_image))
    if String.contains?(raw_func, "force_refresh_images = true") do
      IO.puts("[TRACER] WARNING: EventStore.download_hero_image is hardcoding force_refresh_images=true!")
    end

    # Call original function
    unquote(old_download_hero_image).(url)
  end
end

# ===== Patch QuizmeistersDetailJob.process_hero_image =====
old_process_hero_image = Function.capture(TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob, :process_hero_image, 1)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  defp process_hero_image(hero_image_url) do
    # Get force_refresh_images from process dictionary
    force_refresh_images = Process.get(:force_refresh_images, false)

    # Log what we got from the process dictionary
    IO.puts("[TRACER] QuizmeistersDetailJob.process_hero_image has force_refresh_images=#{inspect(force_refresh_images)} in process dictionary")

    # Call original function
    unquote(old_process_hero_image).(hero_image_url)
  end
end

# ===== Run the job =====
IO.puts("\n===== Running job with force_refresh_images=true =====")
job_args = %{"force_refresh_images" => true, "force_update" => true, "limit" => 1}
IO.puts("Job args: #{inspect(job_args)}")

{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(job_args))
IO.puts("Job inserted with ID: #{job.id}")

IO.puts("\nWaiting for job processing...")
IO.puts("You should see [TRACER] messages in the logs showing how the force_refresh flag is used.")
IO.puts("Note: The actual force_refresh value printed in regular logs might still show 'false' if hardcoded values are being used.")

# Wait for job to run
:timer.sleep(10_000)

IO.puts("\n========= TRACING COMPLETED =========")
IO.puts("If you saw [TRACER] messages showing force_refresh=false despite force_refresh_images=true in arguments,")
IO.puts("then the issue is confirmed - the flag is not being propagated correctly through the system.")

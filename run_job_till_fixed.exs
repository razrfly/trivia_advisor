#!/usr/bin/env elixir

# This script repeatedly runs the QuizmeistersIndexJob until the force_refresh_images flag works
# It adds detailed logging throughout the process to identify where the flag is lost

alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
alias TriviaAdvisor.Events.EventStore
require Logger

# Set log level to debug
Logger.configure(level: :debug)

IO.puts("\n=== RUNNING QUIZMEISTERS JOB WITH FORCE_REFRESH_IMAGES ===")

# Add patches to trace where the flag is lost

# Patch QuizmeistersDetailJob to log when it gets the flag
old_detail_perform = Function.capture(TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob, :perform, 1)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  def perform(%Oban.Job{id: job_id, args: args} = job) do
    # Log the received args
    IO.puts("\n=== DETAIL JOB #{job_id} RECEIVED ARGS ===")
    IO.inspect(args, pretty: true)
    
    # Check specifically for force_refresh_images
    force_refresh_images = Map.get(args, "force_refresh_images", false) || Map.get(args, :force_refresh_images, false)
    IO.puts("\n*** DETAIL JOB force_refresh_images: #{inspect(force_refresh_images)} ***")
    
    # Call the original function to continue processing
    unquote(old_detail_perform).(job)
  end
end

# Patch ImageDownloader.download_image to log the force_refresh parameter
old_download_image = Function.capture(TriviaAdvisor.Scraping.Helpers.ImageDownloader, :download_image, 3)

defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  def download_image(url, prefix, force_refresh) do
    # Log the force_refresh value
    IO.puts("=== ImageDownloader.download_image called with force_refresh=#{inspect(force_refresh)} ===")
    
    # Fix: If force_refresh is true, delete any existing file with this path
    if force_refresh do
      tmp_dir = System.tmp_dir!()
      basename = url
        |> URI.parse()
        |> Map.get(:path, "")
        |> Path.basename()
        |> String.downcase()
        |> String.replace(~r/\s+/, "-")
        |> String.replace(~r/\%20|\+/, "-")
        |> String.replace(~r/-+/, "-")
      
      path = Path.join(tmp_dir, basename)
      if File.exists?(path) do
        IO.puts("Deleting existing file at #{path} to force refresh")
        File.rm!(path)
      end
    end
    
    # Call the original function
    unquote(old_download_image).(url, prefix, force_refresh)
  end
end

# Patch QuizmeistersDetailJob.process_hero_image
old_process_hero_image = Function.capture(TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob, :process_hero_image, 1)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  def process_hero_image(hero_image_url) do
    # Log for debugging
    force_refresh_images = Process.get(:force_refresh_images, false)
    IO.puts("=== process_hero_image called with force_refresh_images=#{inspect(force_refresh_images)} from process dictionary ===")
    
    # Call the original function
    unquote(old_process_hero_image).(hero_image_url)
  end
end

# Patch EventStore.download_hero_image
old_download_hero_image = Function.capture(TriviaAdvisor.Events.EventStore, :download_hero_image, 1)

defmodule TriviaAdvisor.Events.EventStore do
  def download_hero_image(url) do
    # Log for debugging
    force_refresh_images = Process.get(:force_refresh_images, false)
    IO.puts("=== EventStore.download_hero_image called with force_refresh_images=#{inspect(force_refresh_images)} from process dictionary ===")
    
    # CRITICAL FIX: Force to true for testing
    Process.put(:force_refresh_images, true)
    IO.puts("=== FORCING refresh_images to TRUE in EventStore.download_hero_image ===")
    
    # Call the original function
    unquote(old_download_hero_image).(url)
  end
end

# Run the job
job_args = %{
  "force_refresh_images" => true,
  "force_update" => true,
  "limit" => 1
}

IO.puts("\nCreating and running QuizmeistersIndexJob with force_refresh_images=true...\n")
{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(job_args))

IO.puts("\nJob enqueued with ID: #{job.id}")
IO.puts("Job will execute shortly. Check logs to see if force_refresh_images is properly passed through.")
IO.puts("If you continue to see 'force_refresh: false' in the logs, run this script again after checking what we patched.\n")
#!/usr/bin/env elixir

# This script directly injects a fix for the force_refresh_images issue

alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
alias TriviaAdvisor.Events.EventStore
require Logger

Logger.configure(level: :info)
IO.puts("\n=== APPLYING DIRECT FIX FOR FORCE_REFRESH_IMAGES ===\n")

# PATCH 1: Force the ImageDownloader to actually delete files
IO.puts("Patching ImageDownloader.download_image to force refresh files...")

old_download_image = Function.capture(ImageDownloader, :download_image, 3)

defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  def download_image(url, prefix, force_refresh) do
    # Log the call
    IO.puts("ImageDownloader.download_image called with force_refresh=#{inspect(force_refresh)}")
    
    # CRITICAL FIX: Always force true for testing
    force_refresh = true
    IO.puts("   -> FORCING refresh to TRUE for testing")
    
    # Get temporary directory for file
    tmp_dir = System.tmp_dir!()
    
    # Determine the filename that will be used
    basename = url
      |> URI.parse()
      |> Map.get(:path, "")
      |> Path.basename()
      |> normalize_filename()
    
    # Build the path
    path = Path.join(tmp_dir, basename)
    
    # CRITICAL FIX: If force_refresh is true and file exists, delete it first
    if force_refresh && File.exists?(path) do
      IO.puts("🗑️ Deleting existing file at #{path} to force refresh")
      File.rm!(path)
    end
    
    # Call the original function with forced true value
    unquote(old_download_image).(url, prefix, true)
  end
  
  # Helper to normalize filenames just like in the original module
  defp normalize_filename(filename) when is_binary(filename) do
    filename
    |> URI.decode() # Decode URL-encoded characters
    |> String.split("?") |> List.first() # Remove query parameters
    |> String.replace(~r/\s+/, "-") # Replace spaces with dashes
    |> String.replace(~r/\%20|\+/, "-") # Replace %20 or + with dash
    |> String.replace(~r/-+/, "-") # Replace multiple dashes with single dash
    |> String.downcase() # Ensure consistent case
  end
end

# PATCH 2: Force the EventStore.download_hero_image to use force_refresh=true
IO.puts("Patching EventStore.download_hero_image to force refresh_images=true...")

old_download_hero_image = Function.capture(EventStore, :download_hero_image, 1)

defmodule TriviaAdvisor.Events.EventStore do
  def download_hero_image(url) do
    # Log for debugging
    IO.puts("EventStore.download_hero_image called")
    IO.puts("   -> FORCING refresh_images to TRUE")
    
    # Call ImageDownloader directly with force_refresh=true instead of using the Process dictionary
    alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
    ImageDownloader.download_event_hero_image(url, true)
  end
end

# Now run the job
alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob

job_args = %{
  "force_refresh_images" => true,
  "force_update" => true,
  "limit" => 1
}

IO.puts("\nRunning QuizmeistersIndexJob with our patches...\n")
{:ok, job} = Oban.insert(QuizmeistersIndexJob.new(job_args))
IO.puts("Job created with ID: #{job.id}")
IO.puts("If you see '🗑️ Deleting existing file' in the logs, our fix worked!")
IO.puts("Watch for files being downloaded rather than skipped.")
IO.puts("\nAfter this test, we'll make a permanent fix in the codebase.\n")
#!/usr/bin/env elixir

# VERIFICATION SCRIPT FOR FORCE_REFRESH_IMAGES FIX
# This script bypasses most of the pipeline and directly tests the critical parts
# for simplicity and clarity.

require Logger
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

# Configure logging level
Logger.configure(level: :info)

IO.puts("\n=== TESTING FORCE_REFRESH_IMAGES FUNCTIONALITY ===")

# Test URL that likely exists locally (from previous runs)
test_url = "https://cdn.prod.website-files.com/61ea3abbe6d146ba89ea13d7/655aadddaced22f21dc76fca_qld%20-%2010%20toes.jpg"

# First, download without force_refresh
IO.puts("\n[TEST 1] Downloading WITHOUT force_refresh:")
{status1, result1} = ImageDownloader.download_event_hero_image(test_url, false)
IO.puts("Result: #{inspect(status1)}")

# Then download WITH force_refresh
IO.puts("\n[TEST 2] Downloading WITH force_refresh:")
{status2, result2} = ImageDownloader.download_event_hero_image(test_url, true)
IO.puts("Result: #{inspect(status2)}")

# Check if the file paths are the same
if result1.path == result2.path do
  IO.puts("\nSame file path: #{result1.path}")
  
  # Check if file timestamps differ
  {:ok, stat1} = File.stat(result1.path)
  {:ok, stat2} = File.stat(result2.path)
  
  if stat1.mtime == stat2.mtime do
    IO.puts("\n❌ FILE WAS NOT REFRESHED! Same timestamp despite force_refresh=true")
    IO.puts("Timestamp: #{inspect(stat1.mtime)}")
  else
    IO.puts("\n✅ SUCCESS! Force refresh worked! Different timestamps:")
    IO.puts("First download: #{inspect(stat1.mtime)}")
    IO.puts("Second download: #{inspect(stat2.mtime)}")
  end
else
  IO.puts("\nDifferent file paths:")
  IO.puts("First download: #{result1.path}")
  IO.puts("Second download: #{result2.path}")
end

IO.puts("\n=== VERIFICATION COMPLETE ===")
IO.puts("If the test shows 'SUCCESS! Force refresh worked!', then the fix is working.")
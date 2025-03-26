#!/usr/bin/env elixir

# This script tests the image downloading functionality both with and without force_refresh
# to verify that the force_refresh_images flag is working correctly.

alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
require Logger

# Configure logging level
Logger.configure(level: :info)

# Test URL - use a reliable image source
test_url = "https://images.unsplash.com/photo-1559762717-99c81ac85459"

# Function to check file timestamp and size
defp get_file_info(path) do
  case File.stat(path) do
    {:ok, stat} -> {stat.mtime, stat.size}
    _ -> {nil, 0}
  end
end

# First download - standard (non-forced)
IO.puts "\n=== First download (normal) ==="
result1 = ImageDownloader.download_image(test_url, "test_force_refresh", false)
IO.puts "Result: #{inspect(result1)}"

# If successful, get file info
if result1 do
  {mtime1, size1} = get_file_info(result1.path)
  IO.puts "File created at: #{inspect(mtime1)}"
  IO.puts "File size: #{size1} bytes"
  IO.puts "Path: #{result1.path}"
  
  # Wait 2 seconds to ensure timestamps would be different
  :timer.sleep(2000)
  
  # Second download - without force refresh (should reuse file)
  IO.puts "\n=== Second download (without force refresh) ==="
  result2 = ImageDownloader.download_image(test_url, "test_force_refresh", false)
  IO.puts "Result: #{inspect(result2)}"
  
  # Check if the file was reused
  {mtime2, size2} = get_file_info(result2.path)
  IO.puts "File timestamp: #{inspect(mtime2)}"
  IO.puts "File size: #{size2} bytes"
  IO.puts "Path: #{result2.path}"
  
  # Verify if file was reused (timestamps should match)
  if mtime1 == mtime2 do
    IO.puts "✅ File was correctly reused (timestamps match)"
  else
    IO.puts "❌ Expected file to be reused, but timestamps differ!"
  end
  
  # Wait 2 more seconds
  :timer.sleep(2000)
  
  # Third download - with force refresh (should download new file)
  IO.puts "\n=== Third download (with force refresh) ==="
  result3 = ImageDownloader.download_image(test_url, "test_force_refresh", true)
  IO.puts "Result: #{inspect(result3)}"
  
  # Check if new file was downloaded
  {mtime3, size3} = get_file_info(result3.path)
  IO.puts "File timestamp: #{inspect(mtime3)}"
  IO.puts "File size: #{size3} bytes"
  IO.puts "Path: #{result3.path}"
  
  # Verify if new file was downloaded (timestamps should differ)
  if mtime2 != mtime3 do
    IO.puts "✅ File was correctly re-downloaded (timestamps differ)"
  else
    IO.puts "❌ Expected file to be re-downloaded, but timestamps match!"
  end
  
  # Test the event hero image download function too
  IO.puts "\n=== Testing download_event_hero_image ==="
  
  # Without force refresh
  {:ok, hero_result1} = ImageDownloader.download_event_hero_image(test_url, false)
  {hero_mtime1, hero_size1} = get_file_info(hero_result1.path)
  IO.puts "Hero image downloaded without force refresh: #{hero_result1.path}"
  IO.puts "Timestamp: #{inspect(hero_mtime1)}"
  
  :timer.sleep(2000)
  
  # With force refresh
  {:ok, hero_result2} = ImageDownloader.download_event_hero_image(test_url, true)
  {hero_mtime2, hero_size2} = get_file_info(hero_result2.path)
  IO.puts "Hero image downloaded with force refresh: #{hero_result2.path}"
  IO.puts "Timestamp: #{inspect(hero_mtime2)}"
  
  # Verify behavior
  if hero_mtime1 != hero_mtime2 do
    IO.puts "✅ Hero image was correctly re-downloaded with force_refresh=true"
  else
    IO.puts "❌ Expected hero image to be re-downloaded, but timestamps match!"
  end
  
else
  IO.puts "❌ Initial download failed!"
end

IO.puts "\nTest completed!"
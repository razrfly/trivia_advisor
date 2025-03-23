#!/usr/bin/env elixir

# Load the application
Application.put_env(:trivia_advisor, :env, :dev)
Application.ensure_all_started(:trivia_advisor)

require Logger
import Ecto.Query
alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
alias TriviaAdvisor.Events.EventStore
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Source

# Configure more verbose logging for testing
Logger.configure(level: :info)

# Function to get file info including creation time
get_file_info = fn path ->
  case File.stat(path, time: :universal) do
    {:ok, stat} ->
      {:ok, %{
        size: stat.size,
        mtime: stat.mtime,
        formatted_time: NaiveDateTime.to_string(
          NaiveDateTime.from_erl!(stat.mtime, 0)
        )
      }}
    {:error, reason} ->
      {:error, "Could not get file stats: #{reason}"}
  end
end

# Setup reliable test images that don't require DNS resolution
test_image_urls = [
  "https://picsum.photos/200",
  "https://picsum.photos/300"
]

# Use a known venue name that exists in the database
test_venue_name = "White Bear, Ruislip"

# Setup test variables
_image_url = "https://picsum.photos/400"  # Prefixed with _ to indicate intentionally unused

# Test 1: Direct image download without force refresh
Logger.info("💡 TEST 1: Download images without force refresh")

for url <- test_image_urls do
  Logger.info("📥 Downloading image: #{url}")

  # First download - handle possible errors
  case ImageDownloader.download_event_hero_image(url, false) do
    {:ok, upload} ->
      # Get file info after first download
      {:ok, info_1} = get_file_info.(upload.path)
      Logger.info("📄 File created at: #{info_1.formatted_time}, size: #{info_1.size} bytes")

      # Small delay to ensure file modification time would be different
      Process.sleep(2000)

      # Second download without force refresh - should use cached file
      {:ok, upload} = ImageDownloader.download_event_hero_image(url, false)

      # Get file info after second download (should be the same)
      {:ok, info_2} = get_file_info.(upload.path)
      Logger.info("📄 File info after second download: #{info_2.formatted_time}, size: #{info_2.size} bytes")

      # Check if the files were identical (timestamps should match)
      if info_1.mtime == info_2.mtime do
        Logger.info("✅ SUCCESS: File wasn't re-downloaded (cached version used)")
      else
        Logger.error("❌ FAILED: File was re-downloaded even without force_refresh!")
      end

    {:error, reason} ->
      Logger.error("❌ Failed to download image: #{inspect(reason)}, skipping this test")
  end
end

# Test 2: Image download with force refresh
Logger.info("\n💡 TEST 2: Download images with force refresh")

for url <- test_image_urls do
  Logger.info("📥 Downloading image: #{url}")

  # First download - handle possible errors
  case ImageDownloader.download_event_hero_image(url, false) do
    {:ok, upload} ->
      # Get file info after first download
      {:ok, info_1} = get_file_info.(upload.path)
      Logger.info("📄 File created at: #{info_1.formatted_time}, size: #{info_1.size} bytes")

      # Small delay to ensure file modification time would be different
      Process.sleep(2000)

      # Second download WITH force refresh - should download again
      {:ok, upload} = ImageDownloader.download_event_hero_image(url, true)

      # Get file info after forced download
      {:ok, info_2} = get_file_info.(upload.path)
      Logger.info("📄 File info after forced download: #{info_2.formatted_time}, size: #{info_2.size} bytes")

      # Check if the files were different (timestamps should NOT match)
      if info_1.mtime != info_2.mtime do
        Logger.info("✅ SUCCESS: File was re-downloaded with force_refresh")
      else
        Logger.error("❌ FAILED: File wasn't re-downloaded even with force_refresh!")
      end

    {:error, reason} ->
      Logger.error("❌ Failed to download image: #{inspect(reason)}, skipping this test")
  end
end

# Test 3: Test EventStore.process_event with force_refresh_images
Logger.info("\n💡 TEST 3: Test EventStore.process_event with force_refresh_images")

# Helper function to run the venue test
run_venue_test = fn venue ->
  # Get a source ID - try multiple sources
  source = Repo.get_by(Source, name: "Quizmeisters") ||
           Repo.get_by(Source, name: "Question One") ||
           Repo.get_by(Source, name: "Geeks Who Drink") ||
           Repo.one(from s in Source, limit: 1)

  if is_nil(source) do
    Logger.error("❌ No sources found in database. Skipping test 3.")
  else
    # Use a working image URL
    image_url = "https://picsum.photos/400"

    # Process first without force refresh
    Logger.info("📥 Processing event without force refresh for venue: #{venue.name}")

    # Event data with hero image URL
    event_data = %{
      "raw_title" => "Test Event at #{venue.name}",
      "name" => "Test Event",
      "time_text" => "Thursday 20:00",  # Day of week required by EventStore parse_day_of_week
      "description" => "A test event to check force refresh functionality",
      "fee_text" => "Free",
      "source_url" => "https://example.com/test-url",
      "hero_image_url" => image_url,
      "performer_id" => nil
    }

    source_id = 1  # Use a default source ID

    # Process event once - should download the image
    {:ok, {:ok, event}} = EventStore.process_event(venue, event_data, source_id, force_refresh_images: false)

    # Get the hero image path
    hero_image_path = cond do
      is_binary(event.hero_image) ->
        # Simple string path
        Path.join([Application.app_dir(:trivia_advisor), "priv/static", event.hero_image])

      is_map(event.hero_image) && Map.has_key?(event.hero_image, :file_name) ->
        # Map with file_name key
        Path.join([Application.app_dir(:trivia_advisor), "priv/static/uploads/events/hero_images/original", event.hero_image.file_name])

      true ->
        Logger.error("Unsupported hero_image format: #{inspect(event.hero_image)}")
        nil
    end

    if hero_image_path && File.exists?(hero_image_path) do
      # Get file info after first download
      file_info_1 = get_file_info.(hero_image_path)
      Logger.info("📄 Hero image after first download - Created at: #{file_info_1.formatted_time}, size: #{file_info_1.size} bytes")

      # Small delay to ensure timestamps would be different
      Process.sleep(2000)

      # Process same event again WITH force refresh
      Logger.info("📥 Processing same event WITH force refresh")
      {:ok, {:ok, _updated_event}} = EventStore.process_event(venue, event_data, source_id, force_refresh_images: true)

      # Get file info after force refresh download
      file_info_2 = get_file_info.(hero_image_path)
      Logger.info("📄 Hero image after force refresh - Created at: #{file_info_2.formatted_time}, size: #{file_info_2.size} bytes")

      # Compare timestamps
      if file_info_2.mtime > file_info_1.mtime do
        Logger.info("✅ SUCCESS: EventStore.process_event correctly re-downloaded the image with force_refresh")
      else
        Logger.error("❌ FAILURE: EventStore.process_event did not re-download the image with force_refresh")
      end
    else
      Logger.error("❌ Hero image file not found: #{hero_image_path}")
    end
  end
end

# Try to use an actual venue and image
case Repo.get_by(Venue, name: test_venue_name) do
  nil ->
    Logger.error("❌ Test venue '#{test_venue_name}' not found. Trying a different venue...")
    # Try with any venue
    case Repo.one(from v in Venue, limit: 1) do
      nil ->
        Logger.error("❌ No venues found in database. Skipping test 3.")
      venue ->
        run_venue_test.(venue)
    end

  venue ->
    run_venue_test.(venue)
end

Logger.info("\n✅ Force refresh images test completed! 🎉")

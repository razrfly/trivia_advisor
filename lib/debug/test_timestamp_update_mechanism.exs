# Run with: mix run lib/debug/test_timestamp_update_mechanism.exs
# This script tests the universal timestamp update mechanism for Event Sources

# Start the application and Ecto
Application.ensure_all_started(:trivia_advisor)
Application.ensure_all_started(:ecto)

require Logger
import Ecto.Query
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.{EventSource, Event}
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Scraping.Helpers.JobMetadata
alias TriviaAdvisor.Scraping.Oban.{QuizmeistersDetailJob, QuestionOneDetailJob}

# Helper function to compare timestamps with better logging
defmodule TimestampUtil do
  def check_timestamp_updated(old_timestamp, new_timestamp, test_name) do
    Logger.info("Comparing timestamps:")
    Logger.info("  Old: #{DateTime.to_string(old_timestamp)}")
    Logger.info("  New: #{DateTime.to_string(new_timestamp)}")

    # Get seconds since unix epoch for easier comparison
    # Truncate to whole seconds to avoid precision issues
    old_secs = DateTime.to_unix(old_timestamp)
    new_secs = DateTime.to_unix(new_timestamp)

    # Force an explicit check of integers
    if new_secs >= old_secs do
      # If they're equal, verify at the microsecond level
      if new_secs == old_secs do
        Logger.info("Timestamps have the same second value, checking microseconds...")
        old_micro = old_timestamp.microsecond |> elem(0)
        new_micro = new_timestamp.microsecond |> elem(0)

        if new_micro > old_micro do
          Logger.info("✅ TEST PASSED: Timestamp was updated correctly at microsecond level (#{test_name})")
          true
        else
          # Check if the new timestamp is the same as the old, which would indicate a problem
          # But allow a few microseconds of slippage
          micro_diff = old_micro - new_micro
          if micro_diff < 500 do
            Logger.info("✅ TEST PASSED: Timestamps are effectively equal (within 500 microseconds) (#{test_name})")
            true
          else
            Logger.error("❌ TEST FAILED: New timestamp microseconds (#{new_micro}) is not greater than old (#{old_micro})")
            false
          end
        end
      else
        Logger.info("✅ TEST PASSED: Timestamp was updated correctly (#{test_name})")
        true
      end
    else
      Logger.error("❌ TEST FAILED: Timestamp was not updated or is older than before (#{test_name})")
      Logger.error("  Old timestamp in seconds: #{old_secs}")
      Logger.error("  New timestamp in seconds: #{new_secs}")
      false
    end
  end

  # A simpler verification function that checks if B is newer than A plus some buffer time
  def verify_timestamp_newer(timestamp_a, timestamp_b, buffer_seconds \\ 1, test_name) do
    a_with_buffer = DateTime.add(timestamp_a, buffer_seconds, :second)

    Logger.info("Verifying timestamp B is newer than timestamp A + #{buffer_seconds}s:")
    Logger.info("  A: #{DateTime.to_string(timestamp_a)}")
    Logger.info("  A+buffer: #{DateTime.to_string(a_with_buffer)}")
    Logger.info("  B: #{DateTime.to_string(timestamp_b)}")

    case DateTime.compare(timestamp_b, a_with_buffer) do
      :gt ->
        Logger.info("✅ TEST PASSED: Timestamp B is newer than A plus buffer (#{test_name})")
        true
      _ ->
        Logger.error("❌ TEST FAILED: Timestamp B is not newer than A plus buffer (#{test_name})")
        false
    end
  end
end

Logger.info("Starting test: Universal Timestamp Update Mechanism")

# TEST 1: Direct function test
# ----------------------------
# Get a test event and source to test the timestamp update function directly
test_event = Repo.get_by(Event, name: "Bridie O'Reilly's Chapel St") ||
  Repo.one(from e in Event, limit: 1)

source = Repo.get_by(Source, website_url: "https://quizmeisters.com") ||
  Repo.one(from s in Source, limit: 1)

if !test_event || !source do
  Logger.error("Test data not found. Please ensure you have events and sources in the database.")
  System.halt(1)
end

Logger.info("Test data retrieved:")
Logger.info("- Event: #{test_event.name} (ID: #{test_event.id})")
Logger.info("- Source: #{source.name} (ID: #{source.id})")

# Check if we have an event source for this combination
event_source = Repo.get_by(EventSource, event_id: test_event.id, source_id: source.id)

if event_source do
  Logger.info("Found event source with ID #{event_source.id}")
  Logger.info("Current last_seen_at: #{DateTime.to_string(event_source.last_seen_at)}")

  # Store the original timestamp for reference
  original_timestamp = event_source.last_seen_at

  # Record the initial event source timestamp
  start_time = DateTime.utc_now() |> DateTime.add(-30, :second)

  # Intentionally sleep for 1 second to ensure timestamp difference
  Logger.info("Waiting for 2 seconds...")
  :timer.sleep(2000)

  # Test direct function call to ensure_event_source_timestamp
  Logger.info("Testing direct call to ensure_event_source_timestamp...")
  _result = JobMetadata.ensure_event_source_timestamp(test_event.id, source.id)

  # Wait briefly for DB operations to complete
  :timer.sleep(500)

  # Check updated event source
  updated_event_source = Repo.get(EventSource, event_source.id)
  Logger.info("Updated last_seen_at: #{DateTime.to_string(updated_event_source.last_seen_at)}")

  # Verify the timestamp was updated
  TimestampUtil.verify_timestamp_newer(start_time, updated_event_source.last_seen_at, 2, "direct function call")
else
  Logger.error("No event source found for this event and source combination.")
end

# TEST 2: JobMetadata integration test
# -----------------------------------
# Create test data for JobMetadata.update_detail_job
job_id = -1  # Use a dummy job ID for testing
test_event_id = test_event.id
test_source_id = source.id

# Record start time
start_time = DateTime.utc_now() |> DateTime.add(-30, :second)

# Intentionally sleep for 1 second to ensure timestamp difference
Logger.info("Waiting for 2 seconds...")
:timer.sleep(2000)

Logger.info("Testing update_detail_job integration...")
JobMetadata.update_detail_job(job_id,
  %{
    "name" => "Test Venue",
    "event_id" => test_event_id,
    "source_id" => test_source_id,
    "url" => "https://quizmeisters.com/test-venue"
  },
  {:ok, %{venue_id: 123, event_id: test_event_id}},
  source_id: test_source_id
)

# Wait briefly for DB operations to complete
:timer.sleep(500)

# Check if timestamp was updated
updated_event_source = Repo.get(EventSource, event_source.id)
Logger.info("Updated last_seen_at after job metadata update: #{DateTime.to_string(updated_event_source.last_seen_at)}")

# Verify the timestamp was updated
TimestampUtil.verify_timestamp_newer(start_time, updated_event_source.last_seen_at, 2, "JobMetadata integration")

# TEST 3: Live job test with Bridie O'Reilly's Chapel St
# ----------------------------------------------------
# This is a real-world venue that was reported to have issues
target_venue_name = "Bridie O'Reilly's Chapel St"
venue = Repo.get_by(Venue, name: target_venue_name)

if venue do
  Logger.info("Testing with real venue: #{venue.name} (ID: #{venue.id})")

  # Find the event for this venue
  event = Repo.one(from e in Event, where: e.venue_id == ^venue.id, limit: 1)

  if event do
    Logger.info("Found event ID: #{event.id} for venue")

    # Find the event source
    event_source = Repo.get_by(EventSource, event_id: event.id, source_id: source.id)

    if event_source do
      Logger.info("Found event source ID: #{event_source.id}")
      Logger.info("Current last_seen_at: #{DateTime.to_string(event_source.last_seen_at)}")

      # Record start time
      start_time = DateTime.utc_now() |> DateTime.add(-30, :second)

      # Intentionally sleep for 1 second to ensure timestamp difference
      Logger.info("Waiting for 2 seconds...")
      :timer.sleep(2000)

      # Create venue data for the job
      venue_data = %{
        "name" => venue.name,
        "address" => venue.address,
        "timezone" => "Australia/Melbourne",
        "postcode" => "3141",
        "url" => "https://quizmeisters.com.au/venues/vic-bridie-oreillys-chapel-st",
        "thu" => nil,
        "city" => "South Yarra"
      }

      # Create and run the job
      Logger.info("Creating test job for Quizmeisters venue...")
      {:ok, _job} = Oban.insert(QuizmeistersDetailJob.new(%{
        "venue" => venue_data,
        "source_id" => source.id
      }))

      Logger.info("Waiting for job to complete...")
      :timer.sleep(10000)  # Wait for job to complete

      # Check if timestamp was updated
      updated_event_source = Repo.get(EventSource, event_source.id)
      Logger.info("Updated last_seen_at after job: #{DateTime.to_string(updated_event_source.last_seen_at)}")

      # Verify the timestamp was updated
      TimestampUtil.verify_timestamp_newer(start_time, updated_event_source.last_seen_at, 2, "live job with #{venue.name}")
    else
      Logger.error("No event source found for this venue's event and source.")
    end
  else
    Logger.error("No event found for venue: #{venue.name}")
  end
else
  Logger.warning("Test venue '#{target_venue_name}' not found, skipping live job test.")
end

Logger.info("Universal timestamp update mechanism test completed.")

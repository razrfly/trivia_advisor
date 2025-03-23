# Run with: mix run lib/debug/test_3rd_space_canberra_venue.exs
# This script tests our universal timestamp update solution specifically for the 3rd Space Canberra venue

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
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

Logger.info("Starting test for '3rd Space Canberra' venue timestamp updates")

# Find the venue
venue = Repo.get_by(Venue, name: "3rd Space Canberra")

if !venue do
  # Try to find by partial name match
  venue = Repo.one(from v in Venue, where: like(v.name, "%3rd Space%"), limit: 1)

  if !venue do
    Logger.error("Could not find '3rd Space Canberra' venue in the database. Please verify the venue exists.")
    System.halt(1)
  end
end

# Get the Quizmeisters source
source = Repo.get_by(Source, website_url: "https://quizmeisters.com")

if !source do
  Logger.error("Could not find Quizmeisters source in the database.")
  System.halt(1)
end

# Find the associated event
event = Repo.one(from e in Event, where: e.venue_id == ^venue.id, limit: 1)

if !event do
  Logger.error("No event found for venue: #{venue.name}")
  System.halt(1)
end

# Find the event source
event_source = Repo.get_by(EventSource, [event_id: event.id, source_id: source.id])

Logger.info("Test data found:")
Logger.info("- Venue: #{venue.name} (ID: #{venue.id})")
Logger.info("- Event: ID #{event.id}, Day #{event.day_of_week}, Time #{event.start_time}")
Logger.info("- Source: #{source.name} (ID: #{source.id})")

if event_source do
  Logger.info("- Event Source: ID #{event_source.id}")
  Logger.info("- Current last_seen_at: #{DateTime.to_string(event_source.last_seen_at)}")
  Logger.info("- Current source_url: #{event_source.source_url}")

  # Record the initial timestamp and create a reference point for verification
  original_timestamp = event_source.last_seen_at
  reference_time = DateTime.utc_now()

  # Create venue data for the job similar to what the scraper would use
  venue_data = %{
    "name" => venue.name,
    "address" => venue.address,
    "url" => "https://quizmeisters.com/venues/act-3rd-space-canberra",
    "postcode" => String.slice(venue.address, -4, 4),
    "city" => "Canberra",
    "custom_fields" => %{
      "trivia_night" => "Thursday 7:00 PM"
    }
  }

  Logger.info("Running QuizmeistersDetailJob with venue data:")
  Logger.info("- Name: #{venue_data["name"]}")
  Logger.info("- Address: #{venue_data["address"]}")
  Logger.info("- URL: #{venue_data["url"]}")

  # Run the job synchronously
  result = case Oban.insert(QuizmeistersDetailJob.new(%{
    "venue" => venue_data,
    "source_id" => source.id
  })) do
    {:ok, job} ->
      Logger.info("Job created with ID: #{job.id}")
      # Wait for the job to complete
      Logger.info("Waiting 30 seconds for job to complete...")
      :timer.sleep(30_000)
      :ok
    {:error, error} ->
      Logger.error("Failed to create job: #{inspect(error)}")
      :error
  end

  if result == :ok do
    # Check if the event source timestamp was updated
    updated_event_source = Repo.get(EventSource, event_source.id)

    if updated_event_source do
      Logger.info("Updated event source found:")
      Logger.info("- New last_seen_at: #{DateTime.to_string(updated_event_source.last_seen_at)}")
      Logger.info("- New source_url: #{updated_event_source.source_url}")

      # Compare timestamps
      old_secs = DateTime.to_unix(original_timestamp)
      new_secs = DateTime.to_unix(updated_event_source.last_seen_at)
      ref_secs = DateTime.to_unix(reference_time)

      if new_secs > old_secs do
        Logger.info("✅ SUCCESS: Timestamp was updated (old: #{old_secs}, new: #{new_secs})")

        if new_secs > ref_secs do
          Logger.info("✅ SUCCESS: New timestamp is newer than our reference time")
        else
          Logger.warning("⚠️ WARNING: New timestamp is older than our reference time")
        end
      else
        Logger.error("❌ FAILED: Timestamp was not updated (old: #{old_secs}, new: #{new_secs})")
        Logger.error("    Original: #{DateTime.to_string(original_timestamp)}")
        Logger.error("    Updated:  #{DateTime.to_string(updated_event_source.last_seen_at)}")
        Logger.error("    Reference: #{DateTime.to_string(reference_time)}")
      end
    else
      Logger.error("❌ FAILED: Could not retrieve updated event source")
    end
  else
    Logger.error("❌ FAILED: Job execution failed")
  end
else
  Logger.error("No event source found for this event and source combination")
end

Logger.info("Test completed")

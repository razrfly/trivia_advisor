# Run with: mix run lib/debug/force_update_3rd_space.exs
# This script directly updates the 3rd Space Canberra event source timestamp using raw SQL

# Start the application and Ecto
Application.ensure_all_started(:trivia_advisor)
Application.ensure_all_started(:ecto)

require Logger
import Ecto.Query
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.{EventSource, Event}
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Source

Logger.info("🔧 EMERGENCY FIX: Forcing timestamp update for 3rd Space Canberra")

# Find the venue
venue = Repo.get_by(Venue, name: "3rd Space Canberra")

if venue do
  Logger.info("✅ Found venue: #{venue.name} (ID: #{venue.id})")

  # Find the event
  event = Repo.one(from e in Event, where: e.venue_id == ^venue.id, limit: 1)

  if event do
    Logger.info("✅ Found event: ID #{event.id}")

    # Find the source
    source = Repo.get_by(Source, website_url: "https://quizmeisters.com")

    if source do
      Logger.info("✅ Found source: #{source.name} (ID: #{source.id})")

      # Find the event source
      event_source = Repo.get_by(EventSource, [event_id: event.id, source_id: source.id])

      if event_source do
        Logger.info("✅ Found event source: ID #{event_source.id}")
        Logger.info("Current last_seen_at: #{DateTime.to_string(event_source.last_seen_at)}")

        # Generate new timestamp
        now = DateTime.utc_now()

        # Direct SQL update to bypass any potential validation issues
        sql = "UPDATE event_sources SET last_seen_at = $1, updated_at = $2 WHERE id = $3"
        params = [now, now, event_source.id]

        Logger.info("🔄 Executing SQL update...")

        case Ecto.Adapters.SQL.query(Repo, sql, params) do
          {:ok, result} ->
            Logger.info("✅ SQL update successful: #{inspect(result.num_rows)} rows affected")

            # Verify the update
            updated_event_source = Repo.get(EventSource, event_source.id)

            if updated_event_source do
              Logger.info("✅ Verification - Updated timestamp: #{DateTime.to_string(updated_event_source.last_seen_at)}")

              if DateTime.compare(updated_event_source.last_seen_at, event_source.last_seen_at) == :gt do
                Logger.info("✅ SUCCESS: Timestamp was updated correctly")
              else
                Logger.error("❌ FAILED: Timestamp was not updated despite successful SQL update")
              end
            else
              Logger.error("❌ FAILED: Could not retrieve updated event source for verification")
            end

          {:error, error} ->
            Logger.error("❌ SQL update failed: #{inspect(error)}")
        end
      else
        Logger.error("❌ Event source not found for event ID #{event.id} and source ID #{source.id}")
      end
    else
      Logger.error("❌ Source 'quizmeisters' not found")
    end
  else
    Logger.error("❌ Event not found for venue ID #{venue.id}")
  end
else
  Logger.error("❌ Venue '3rd Space Canberra' not found")
end

Logger.info("Emergency fix script completed")

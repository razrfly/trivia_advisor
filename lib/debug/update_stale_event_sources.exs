# Run with: mix run lib/debug/update_stale_event_sources.exs
# This script finds and updates event sources with stale timestamps

# Start the application and Ecto
Application.ensure_all_started(:trivia_advisor)
Application.ensure_all_started(:ecto)

require Logger
import Ecto.Query
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.{EventSource, Event}
alias TriviaAdvisor.Scraping.Helpers.JobMetadata

# Configure the threshold for stale timestamps (default: 7 days)
days_threshold = 7

Logger.info("🔍 Finding event sources with timestamps older than #{days_threshold} days")

# Calculate the cutoff date
cutoff_date = DateTime.utc_now() |> DateTime.add(-days_threshold * 24 * 60 * 60, :second)
Logger.info("📅 Cutoff date: #{DateTime.to_string(cutoff_date)}")

# Find event sources with stale timestamps
stale_sources = Repo.all(
  from es in EventSource,
  where: es.last_seen_at < ^cutoff_date,
  order_by: [asc: es.last_seen_at],
  preload: [:event, :source]
)

if stale_sources == [] do
  Logger.info("✅ No stale event sources found!")
else
  Logger.info("🔄 Found #{length(stale_sources)} stale event sources")

  # Group them by source for better reporting
  stale_by_source = stale_sources
    |> Enum.group_by(fn es -> es.source.name end)
    |> Enum.map(fn {source_name, sources} -> {source_name, length(sources)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)

  Logger.info("📊 Stale sources by source type:")
  for {source_name, count} <- stale_by_source do
    Logger.info("  - #{source_name}: #{count} stale sources")
  end

  # Display the 5 oldest timestamps
  oldest = stale_sources |> Enum.take(5)
  Logger.info("⏰ Oldest timestamps:")
  for es <- oldest do
    venue_name = if es.event && es.event.venue_id do
      venue = Repo.get(TriviaAdvisor.Locations.Venue, es.event.venue_id)
      venue && venue.name || "Unknown venue"
    else
      "Unknown venue"
    end
    Logger.info("  - #{venue_name}: #{DateTime.to_string(es.last_seen_at)} (#{es.source.name})")
  end

  # Ask for confirmation before updating
  Logger.info("🔄 Update all stale timestamps? (y/n)")
  IO.puts("🔄 Update all stale timestamps? (y/n)")

  response = IO.gets("") |> String.trim() |> String.downcase()

  if response == "y" do
    Logger.info("🔄 Updating #{length(stale_sources)} stale timestamps...")

    # Use a transaction to ensure all updates succeed or fail together
    Repo.transaction(fn ->
      for es <- stale_sources do
        Logger.info("🔄 Updating event_source #{es.id} for event #{es.event_id}, source #{es.source_id}")
        JobMetadata.force_update_event_source_timestamp(es.event_id, es.source_id, es.source_url)
      end
    end)

    Logger.info("✅ All stale timestamps updated successfully!")
  else
    Logger.info("❌ Update canceled")
  end
end

Logger.info("Script completed")

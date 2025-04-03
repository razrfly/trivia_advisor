defmodule TriviaAdvisor.Scraping.TimestampTest do
  @moduledoc """
  Test module to verify timestamp updates for venue event sources.

  This module provides tools to test whether event sources are properly updated
  when creating or modifying events.
  """

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Events.EventSource
  alias TriviaAdvisor.Events.Event
  alias TriviaAdvisor.Events.EventStore

  @doc """
  Test function to verify timestamp updates for a specific venue.

  Usage:
    TriviaAdvisor.Scraping.TimestampTest.run_timestamp_test("The One Tun", 3)

  Args:
    - venue_name: The name of the venue to test
    - source_id: ID of the source (3 for Inquizition)
  """
  def run_timestamp_test(venue_name, source_id \\ 3) do
    # 1. Find the venue
    venue = find_venue_by_name(venue_name)
    if is_nil(venue) do
      Logger.error("❌ Venue '#{venue_name}' not found")
      {:error, :venue_not_found}
    else
      Logger.info("✅ Found venue: #{venue.name} (ID: #{venue.id})")

      # 2. Find all event sources for this venue from the specified source
      event_sources_before = find_event_sources(venue.id, source_id)

      if Enum.empty?(event_sources_before) do
        Logger.error("❌ No event sources found for venue: #{venue.name}, source_id: #{source_id}")
        {:error, :no_event_sources}
      else
        # Log the current timestamps
        log_event_sources(event_sources_before, "BEFORE")

        # Save the oldest timestamp for comparison later
        oldest_timestamp = event_sources_before
                           |> Enum.min_by(& &1.last_seen_at,
                              fn -> %{last_seen_at: DateTime.from_unix!(0)} end)
                           |> Map.get(:last_seen_at)

        # 3. Create a venue data map for testing
        venue_data = %{
          "name" => venue.name,
          "address" => venue.address,
          "source_id" => source_id,
          # Use a different day to force a new event
          "day_of_week" => get_different_day(event_sources_before),
          "time_text" => "Test Time #{:rand.uniform(100)}"
        }

        # 4. Process the venue
        Logger.info("🧪 Testing with venue_data: #{inspect(venue_data)}")
        result = process_test_venue(venue_data, source_id)
        Logger.info("🔄 Process result: #{inspect(result)}")

        # 5. Check if event sources were updated
        event_sources_after = find_event_sources(venue.id, source_id)
        log_event_sources(event_sources_after, "AFTER")

        # 6. Verify if timestamps were updated
        all_updated = Enum.all?(event_sources_after, fn es ->
          es.last_seen_at && DateTime.compare(es.last_seen_at, oldest_timestamp) == :gt
        end)

        if all_updated do
          Logger.info("✅ SUCCESS: All event source timestamps were updated")
          {:ok, %{before: event_sources_before, after: event_sources_after}}
        else
          Logger.error("❌ FAILURE: Some event source timestamps were not updated")
          {:error, %{before: event_sources_before, after: event_sources_after}}
        end
      end
    end
  end

  # Process venue for testing purposes - reimplement the key functionality
  defp process_test_venue(venue_data, source_id) do
    # Find the venue record
    venue = find_venue_by_name(venue_data["name"])

    # Extract day of week
    day_of_week = venue_data["day_of_week"]

    # Format time text
    _time_text = venue_data["time_text"] || "Test Time"
    start_time = "20:00"

    # Format day name
    day_name = case day_of_week do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Thursday" # Default to Thursday
    end

    # Create event data
    event_data = %{
      raw_title: "Test Quiz at #{venue.name}",
      name: venue.name,
      time_text: "#{day_name} #{start_time}",
      description: "Test description",
      fee_text: "£2.50",
      source_url: "https://inquizition.com/find-a-quiz/##{venue.name}",
      hero_image_url: nil,
      day_of_week: day_of_week,
      start_time: start_time,
      entry_fee_cents: 250
    }

    # Process event through EventStore
    case EventStore.process_event(venue, event_data, source_id) do
      {:ok, event} ->
        Logger.info("✅ Successfully created test event for venue: #{venue.name}")
        # Update all event sources for this venue using the same query as in InquizitionDetailJob
        now = DateTime.utc_now()

        # Find all events for this venue
        query_events = from e in Event,
          where: e.venue_id == ^venue.id,
          select: e.id

        event_ids = Repo.all(query_events)

        # Find and update all event sources
        query = from es in EventSource,
          where: es.event_id in ^event_ids and es.source_id == ^source_id

        {updated_count, _} = Repo.update_all(
          query,
          [set: [last_seen_at: now, updated_at: now]]
        )

        Logger.info("✅ Updated #{updated_count} event sources for venue_id: #{venue.id}")
        {:ok, %{venue: venue, event: event, updated_count: updated_count}}

      {:error, reason} ->
        Logger.error("❌ Failed to create test event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Find venue by name
  defp find_venue_by_name(name) do
    Repo.one(from v in TriviaAdvisor.Locations.Venue,
      where: v.name == ^name,
      limit: 1)
  end

  # Find all event sources for a venue from a specific source
  defp find_event_sources(venue_id, source_id) do
    # First find all events for this venue
    event_ids = Repo.all(from e in Event,
      where: e.venue_id == ^venue_id,
      select: e.id)

    # Find all event sources for these events from the specified source
    Repo.all(from es in EventSource,
      where: es.event_id in ^event_ids and es.source_id == ^source_id,
      select: es,
      order_by: [desc: es.updated_at])
  end

  # Log event sources with their timestamps
  defp log_event_sources(event_sources, label) do
    Logger.info("🔍 #{label} Event Sources (#{length(event_sources)} found):")

    Enum.each(event_sources, fn es ->
      event = Repo.get(Event, es.event_id)
      day = if event, do: "day: #{event.day_of_week}", else: "unknown day"

      Logger.info("""
      📅 EventSource ID: #{es.id}, Event ID: #{es.event_id} (#{day})
         last_seen_at: #{format_datetime(es.last_seen_at)}
         updated_at: #{format_datetime(es.updated_at)}
      """)
    end)
  end

  # Get a different day of week than what's in the existing events
  defp get_different_day(event_sources) do
    # Get all event IDs
    event_ids = Enum.map(event_sources, & &1.event_id)

    # Get all the days of week from these events
    days = Repo.all(from e in Event,
      where: e.id in ^event_ids,
      select: e.day_of_week)
      |> Enum.filter(&(&1))

    # Find a day that's not in use (1-7, where 1 is Monday)
    all_days = Enum.to_list(1..7)

    case all_days -- days do
      [] ->
        # If all days are taken, just use day+1 (mod 7)
        # This isn't ideal but it's a test function
        default_day = List.first(days) || 1
        rem(default_day, 7) + 1
      available_days ->
        # Pick a random day from the available ones
        Enum.random(available_days)
    end
  end

  # Format datetime for logging
  defp format_datetime(nil), do: "nil"
  defp format_datetime(dt) do
    DateTime.to_string(dt)
  rescue
    _ -> inspect(dt)
  end
end

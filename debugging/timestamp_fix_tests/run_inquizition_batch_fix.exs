# Script to find and update all "old" Inquizition venues (not updated in 20+ days)
require Logger
Logger.configure(level: :info)
IO.puts("Starting batch fix for old Inquizition venues")

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.EventSource
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob
import Ecto.Query

# Helper function to convert day_of_week number to name
day_name = fn day ->
  case day do
    1 -> "Monday"
    2 -> "Tuesday"
    3 -> "Wednesday"
    4 -> "Thursday"
    5 -> "Friday"
    6 -> "Saturday"
    7 -> "Sunday"
    _ -> "Unknown"
  end
end

# Helper function to format time (e.g., "19:30" -> "7:30pm")
format_time = fn time ->
  if is_binary(time) do
    case String.split(time, ":") do
      [hours, minutes] ->
        hours_int = String.to_integer(hours)
        {display_hours, ampm} =
          if hours_int >= 12 do
            {(if hours_int > 12 do hours_int - 12 else hours_int end), "pm"}
          else
            {(if hours_int == 0 do 12 else hours_int end), "am"}
          end
        "#{display_hours}:#{minutes}#{ampm}"
      _ -> time
    end
  else
    "Unknown time"
  end
end

# Config: how many days is considered "old"
old_days_threshold = 20

# Get the Inquizition source ID
source = Repo.get_by!(Source, name: "inquizition")
source_id = source.id
IO.puts("Using source: #{source.name} (ID: #{source_id})")

# Find all events with event sources from this source
old_cutoff_date = DateTime.utc_now() |> DateTime.add(-old_days_threshold * 24 * 3600, :second)
IO.puts("Finding venues not updated since: #{DateTime.to_string(old_cutoff_date)}")

# First get all event sources that are older than our threshold
query = from es in EventSource,
  join: e in Event, on: es.event_id == e.id,
  join: v in Venue, on: e.venue_id == v.id,
  where: es.source_id == ^source_id and es.last_seen_at < ^old_cutoff_date,
  distinct: [v.id],
  select: {v.id, v.name, v.address, e.day_of_week, e.start_time, es.last_seen_at}

old_venues = Repo.all(query)
IO.puts("\nFound #{length(old_venues)} venues that haven't been updated in #{old_days_threshold}+ days:")

# Display the venues and create detail jobs for each
venue_count = length(old_venues)
old_venues
|> Enum.with_index(1)
|> Enum.each(fn {{venue_id, name, address, day_of_week, start_time, last_seen_at}, index} ->
  days_old = DateTime.diff(DateTime.utc_now(), last_seen_at, :day)

  IO.puts("\n[#{index}/#{venue_count}] #{name}")
  IO.puts("  Address: #{address}")
  IO.puts("  Event day: #{day_of_week}, start time: #{start_time}")
  IO.puts("  Last updated: #{DateTime.to_string(last_seen_at)} (#{days_old} days ago)")

  # Create venue_data similar to what the index job would create
  venue_data = %{
    "name" => name,
    "address" => address,
    "source_id" => source_id,
    "day_of_week" => day_of_week,
    "start_time" => start_time,
    "time_text" => day_name.(day_of_week) <> ", " <> format_time.(start_time)
  }

  # Queue a detail job to update this venue with a short delay between jobs
  {:ok, job} = Oban.insert(
    InquizitionDetailJob.new(%{venue_data: venue_data, force_update: true}),
    schedule_in: index * 2 # 2 seconds between jobs to avoid overwhelming the system
  )

  IO.puts("  → Scheduled detail job with ID: #{job.id}")
end)

IO.puts("\n✅ Successfully scheduled #{venue_count} venues for update")
IO.puts("Each venue will be processed with a 2 second delay between jobs")
IO.puts("The entire batch should complete in approximately #{div(venue_count * 2, 60)} minutes")

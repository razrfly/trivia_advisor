alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Events.Performer
import Ecto.Query

# Count events with performer_ids
events_with_performers = Repo.one(
  from e in Event,
  where: not is_nil(e.performer_id),
  select: count(e.id)
)

IO.puts("Total events with performers: #{events_with_performers}")

# Count unique performers used in events
unique_performers = Repo.all(
  from e in Event,
  where: not is_nil(e.performer_id),
  distinct: true,
  select: e.performer_id
) |> length

IO.puts("Unique performers used in events: #{unique_performers}")

# Check for performers with multiple events
performer_counts = Repo.all(
  from e in Event,
  where: not is_nil(e.performer_id),
  group_by: e.performer_id,
  select: {e.performer_id, count(e.id)}
)

performers_with_multiple_events = Enum.filter(performer_counts, fn {_id, count} -> count > 1 end)

IO.puts("Performers with multiple events: #{length(performers_with_multiple_events)}")

# Display performers with multiple events
if length(performers_with_multiple_events) > 0 do
  IO.puts("\nPerformers with multiple events:")

  Enum.each(performers_with_multiple_events, fn {performer_id, count} ->
    performer = Repo.get(Performer, performer_id)
    events = Repo.all(
      from e in Event,
      where: e.performer_id == ^performer_id,
      preload: [:venue]
    )

    IO.puts("  Performer: #{performer.name} (ID: #{performer.id}) - #{count} events")

    Enum.each(events, fn event ->
      IO.puts("    - #{event.name} at #{event.venue.name} (Event ID: #{event.id})")
    end)
  end)
end

# Count total performers
total_performers = Repo.one(from p in Performer, where: p.source_id == 4, select: count(p.id))
IO.puts("\nTotal Quizmeisters performers: #{total_performers}")

# Check if there are any duplicate performer names
duplicate_performers = Repo.all(
  from p in Performer,
  where: p.source_id == 4,
  group_by: p.name,
  having: count(p.id) > 1,
  select: {p.name, count(p.id)}
)

IO.puts("Duplicate performer names: #{length(duplicate_performers)}")

if length(duplicate_performers) > 0 do
  IO.puts("\nDuplicate performer names:")

  Enum.each(duplicate_performers, fn {name, count} ->
    performers = Repo.all(
      from p in Performer,
      where: p.name == ^name and p.source_id == 4
    )

    IO.puts("  Name: #{name} - #{count} performers")

    Enum.each(performers, fn performer ->
      IO.puts("    - Performer ID: #{performer.id}")
    end)
  end)
end

defmodule TriviaAdvisor.Events.EventStore do
  @moduledoc """
  Handles creating and updating events and their sources.
  """

  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Events.{Event, EventSource}
  require Logger

  # Import only the parse_currency function
  import Event, only: [parse_currency: 2]

  @doc """
  Process event data from a scraper, creating or updating the event and its source.
  If day_of_week changes, creates a new event instead of updating.
  """
  def process_event(venue, event_data, source_id) do
    # Preload required associations
    venue = Repo.preload(venue, [city: :country])

    # Parse frequency from the raw title
    frequency = parse_event_frequency(event_data.raw_title)

    attrs = %{
      name: event_data.raw_title,  # Keep the raw title
      venue_id: venue.id,
      day_of_week: parse_day_of_week(event_data.time_text),
      start_time: parse_time(event_data.time_text),
      frequency: frequency,
      entry_fee_cents: parse_currency(event_data.fee_text, venue),
      description: event_data.description,
      hero_image_url: event_data.hero_image_url
    }

    Repo.transaction(fn ->
      # First try to find by venue and day
      existing_event = find_existing_event(attrs.venue_id, attrs.day_of_week)

      case existing_event do
        nil ->
          # Create new event if none exists
          with {:ok, event} <- create_event(attrs),
               {:ok, _source} <- create_event_source(event, source_id) do
            {:ok, event}
          end

        event ->
          # Update existing event if fields changed
          if event_changed?(event, attrs) do
            with {:ok, updated_event} <- update_event(event, attrs),
                 {:ok, _source} <- update_event_source(updated_event, source_id) do
              {:ok, updated_event}
            end
          else
            # Just update the source timestamp if no changes
            {:ok, _source} = update_event_source(event, source_id)
            {:ok, event}
          end
      end
    end)
  end

  defp find_existing_event(venue_id, day_of_week) do
    Repo.one(
      from e in Event,
      where: e.venue_id == ^venue_id and
             e.day_of_week == ^day_of_week,
      limit: 1
    )
  end

  defp create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  defp update_event(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  defp create_event_source(event, source_id) do
    %EventSource{}
    |> EventSource.changeset(%{
      event_id: event.id,
      source_id: source_id,
      last_seen_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  defp update_event_source(event, source_id) do
    case Repo.get_by(EventSource, event_id: event.id, source_id: source_id) do
      nil -> create_event_source(event, source_id)
      source ->
        source
        |> EventSource.changeset(%{last_seen_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  defp event_changed?(event, attrs) do
    Map.take(event, [:start_time, :frequency, :entry_fee_cents, :description, :hero_image_url]) !=
    Map.take(attrs, [:start_time, :frequency, :entry_fee_cents, :description, :hero_image_url])
  end

  defp parse_day_of_week("Monday" <> _), do: 1
  defp parse_day_of_week("Tuesday" <> _), do: 2
  defp parse_day_of_week("Wednesday" <> _), do: 3
  defp parse_day_of_week("Thursday" <> _), do: 4
  defp parse_day_of_week("Friday" <> _), do: 5
  defp parse_day_of_week("Saturday" <> _), do: 6
  defp parse_day_of_week("Sunday" <> _), do: 7

  defp parse_time(time_text) do
    # Extract time from format like "Wednesday 20:00"
    case Regex.run(~r/\d{2}:\d{2}/, time_text) do
      [time] -> Time.from_iso8601!(time <> ":00")
      nil -> raise "Invalid time format: #{time_text}"
    end
  end

  # Parse frequency from event title
  defp parse_event_frequency(title) do
    title = String.downcase(title)
    cond do
      # Check for explicit monthly patterns with ordinals
      (String.contains?(title, ["first", "second", "third", "fourth", "last"]) and
       String.contains?(title, ["of the month", "of every month"])) or
      String.contains?(title, ["monthly"]) ->
        :monthly

      # Check for biweekly/fortnightly patterns
      String.contains?(title, ["every other", "bi-weekly", "biweekly", "fortnightly"]) ->
        :biweekly

      # Everything else is weekly (default for pub quizzes)
      true ->
        :weekly
    end
  end
end

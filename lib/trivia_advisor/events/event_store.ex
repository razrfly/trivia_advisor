defmodule TriviaAdvisor.Events.EventStore do
  @moduledoc """
  Handles creating and updating events and their sources.
  """

  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Events.{Event, EventSource}
  require Logger

  # Import the parse functions from Event module
  import Event, only: [parse_frequency: 1, parse_currency: 2]

  @doc """
  Process event data from a scraper, creating or updating the event and its source.
  """
  def process_event(venue, event_data, source_id) do
    # Extract required event attributes
    attrs = %{
      venue_id: venue.id,
      day_of_week: parse_day_of_week(event_data.time_text),
      start_time: parse_time(event_data.time_text),
      frequency: parse_frequency(event_data.description),
      entry_fee_cents: parse_currency(event_data.fee_text, venue),
      description: event_data.description,
      hero_image_url: event_data.hero_image_url
    }

    Repo.transaction(fn ->
      with {:ok, event} <- find_or_create_event(attrs),
           {:ok, _source} <- find_or_create_event_source(event, source_id) do
        {:ok, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp find_or_create_event(attrs) do
    # First try to find existing event
    case Repo.one(
      from e in Event,
      where: e.venue_id == ^attrs.venue_id and
             e.day_of_week == ^attrs.day_of_week,
      limit: 1
    ) do
      nil ->
        %Event{}
        |> Event.changeset(attrs)
        |> Repo.insert()

      event ->
        # Only update if there are actual changes
        if event_changed?(event, attrs) do
          event
          |> Event.changeset(attrs)
          |> Repo.update()
        else
          {:ok, event}
        end
    end
  end

  defp find_or_create_event_source(event, source_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(EventSource, event_id: event.id, source_id: source_id) do
      nil ->
        %EventSource{}
        |> EventSource.changeset(%{
          event_id: event.id,
          source_id: source_id,
          last_seen_at: now
        })
        |> Repo.insert()

      source ->
        source
        |> EventSource.changeset(%{last_seen_at: now})
        |> Repo.update()
    end
  end

  defp event_changed?(event, attrs) do
    Map.take(event, [:day_of_week, :start_time, :frequency, :entry_fee_cents, :description, :hero_image_url]) !=
    Map.take(attrs, [:day_of_week, :start_time, :frequency, :entry_fee_cents, :description, :hero_image_url])
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
end

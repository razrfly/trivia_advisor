defmodule TriviaAdvisorWeb.Live.Admin.VenueStatistics do
  use TriviaAdvisorWeb, :live_view

  require Logger
  alias TriviaAdvisor.{Repo, Locations}
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Events.{Event, EventSource}
  alias TriviaAdvisor.Scraping.Source
  import Ecto.Query, warn: false

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:loading, true)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    statistics = load_venue_statistics()

    socket = socket
    |> assign(:page_title, "Venue Statistics")
    |> assign(:statistics, statistics)
    |> assign(:loading, false)

    {:noreply, socket}
  end

  defp load_venue_statistics do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    # Total venues
    total_venues = Venue |> Repo.aggregate(:count, :id)

    # New venues in last 30 days
    new_venues_30d = from(v in Venue,
                         where: v.inserted_at >= ^thirty_days_ago)
                    |> Repo.aggregate(:count, :id)

    # Active venues in last 30 days (venues with events that have been seen recently)
    active_venues_30d = from(v in Venue,
                            join: e in Event, on: e.venue_id == v.id,
                            join: es in EventSource, on: es.event_id == e.id,
                            where: es.last_seen_at >= ^thirty_days_ago,
                            select: v.id,
                            distinct: true)
                       |> Repo.all()
                       |> length()

    # Stale venues (venues not seen in last 30 days but exist)
    stale_venues = from(v in Venue,
                       left_join: e in Event, on: e.venue_id == v.id,
                       left_join: es in EventSource, on: es.event_id == e.id,
                       group_by: v.id,
                       having: is_nil(max(es.last_seen_at)) or max(es.last_seen_at) < ^thirty_days_ago,
                       select: v.id)
                  |> Repo.all()
                  |> length()

    # Source-based statistics
    source_stats = load_source_statistics(thirty_days_ago)

    %{
      total_venues: total_venues,
      new_venues_30d: new_venues_30d,
      active_venues_30d: active_venues_30d,
      stale_venues: stale_venues,
      source_statistics: source_stats,
      last_updated: DateTime.utc_now()
    }
  end

  defp load_source_statistics(thirty_days_ago) do
    # Get all sources
    sources = Repo.all(Source)

    Enum.map(sources, fn source ->
      # Total venues for this source
      total_venues = from(v in Venue,
                         join: e in Event, on: e.venue_id == v.id,
                         join: es in EventSource, on: es.event_id == e.id,
                         where: es.source_id == ^source.id,
                         select: v.id,
                         distinct: true)
                    |> Repo.all()
                    |> length()

            # Active venues in last 30 days for this source
      active_venues_30d = from(v in Venue,
                              join: e in Event, on: e.venue_id == v.id,
                              join: es in EventSource, on: es.event_id == e.id,
                              where: es.source_id == ^source.id and
                                     es.last_seen_at >= ^thirty_days_ago,
                              select: v.id,
                              distinct: true)
                         |> Repo.all()
                         |> length()

            # New venues in last 30 days for this source
      # (venues that were first seen by this source in the last 30 days)
      new_venues_30d = from(v in Venue,
                           join: e in Event, on: e.venue_id == v.id,
                           join: es in EventSource, on: es.event_id == e.id,
                           where: es.source_id == ^source.id and
                                  v.inserted_at >= ^thirty_days_ago,
                           select: v.id,
                           distinct: true)
                      |> Repo.all()
                      |> length()

      # Stale venues for this source (not seen in last 30 days)
      stale_venues = from(v in Venue,
                         join: e in Event, on: e.venue_id == v.id,
                         join: es in EventSource, on: es.event_id == e.id,
                         where: es.source_id == ^source.id,
                         group_by: v.id,
                         having: max(es.last_seen_at) < ^thirty_days_ago,
                         select: v.id)
                    |> Repo.all()
                    |> length()

      %{
        source: source,
        total_venues: total_venues,
        active_venues_30d: active_venues_30d,
        new_venues_30d: new_venues_30d,
        stale_venues: stale_venues
      }
    end)
    |> Enum.sort_by(& &1.total_venues, :desc)
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Logger.info("🔄 Admin triggered venue statistics refresh")

    socket = socket
    |> assign(:loading, true)
    |> assign(:statistics, load_venue_statistics())
    |> assign(:loading, false)
    |> put_flash(:info, "Statistics refreshed successfully!")

    {:noreply, socket}
  end

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_percentage(numerator, denominator) when denominator > 0 do
    percentage = (numerator / denominator * 100) |> Float.round(1)
    "#{percentage}%"
  end
  defp format_percentage(_, _), do: "0%"
end

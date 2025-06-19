defmodule TriviaAdvisorWeb.Live.Admin.VenueStatistics do
  use TriviaAdvisorWeb, :live_view

  require Logger
  alias TriviaAdvisor.Repo
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
    # Get all sources first
    sources = Repo.all(Source)

    # Get venue counts per source in a single query
    venue_counts = from(s in Source,
      left_join: v in Venue,
        on: true,
      left_join: e in Event,
        on: e.venue_id == v.id,
      left_join: es in EventSource,
        on: es.event_id == e.id and es.source_id == s.id,
      where: not is_nil(es.source_id),
      group_by: s.id,
      select: {s.id, count(v.id, :distinct)}
    ) |> Repo.all() |> Map.new()

    # Get active venue counts (last 30 days)
    active_counts = from(s in Source,
      left_join: v in Venue,
        on: true,
      left_join: e in Event,
        on: e.venue_id == v.id,
      left_join: es in EventSource,
        on: es.event_id == e.id and es.source_id == s.id,
      where: not is_nil(es.source_id) and es.last_seen_at >= ^thirty_days_ago,
      group_by: s.id,
      select: {s.id, count(v.id, :distinct)}
    ) |> Repo.all() |> Map.new()

    # Get new venue counts (inserted in last 30 days)
    new_counts = from(s in Source,
      left_join: v in Venue,
        on: true,
      left_join: e in Event,
        on: e.venue_id == v.id,
      left_join: es in EventSource,
        on: es.event_id == e.id and es.source_id == s.id,
      where: not is_nil(es.source_id) and v.inserted_at >= ^thirty_days_ago,
      group_by: s.id,
      select: {s.id, count(v.id, :distinct)}
    ) |> Repo.all() |> Map.new()

    # Calculate stale venues (total - active)
    sources
    |> Enum.map(fn source ->
      total = Map.get(venue_counts, source.id, 0)
      active = Map.get(active_counts, source.id, 0)
      new = Map.get(new_counts, source.id, 0)
      stale = total - active

      %{
        source: source,
        total_venues: total,
        active_venues_30d: active,
        new_venues_30d: new,
        stale_venues: max(stale, 0)
      }
    end)
    |> Enum.sort_by(& &1.total_venues, :desc)
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Logger.info("🔄 Admin triggered venue statistics refresh")

    socket = assign(socket, :loading, true)

    try do
      statistics = load_venue_statistics()
      socket = socket
      |> assign(:statistics, statistics)
      |> assign(:loading, false)
      |> put_flash(:info, "Statistics refreshed successfully!")

      {:noreply, socket}
    rescue
      e ->
        Logger.error("Failed to load venue statistics: #{inspect(e)}")
        socket = socket
        |> assign(:loading, false)
        |> put_flash(:error, "Failed to refresh statistics. Please try again.")

        {:noreply, socket}
    end
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

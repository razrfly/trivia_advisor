defmodule TriviaAdvisorWeb.Components.WorldMapComponent do
  use TriviaAdvisorWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="world-map-container" id={"world-map-#{@id}"} phx-hook="WorldMap" data-venues={Jason.encode!(@venues_by_country)}>
      <div class="flex items-center justify-center mb-6">
        <div class="stats-container flex gap-8 text-center">
          <div class="venues-count">
            <div class="text-4xl font-bold text-indigo-600"><%= @venues_count %>+</div>
            <div class="text-gray-600">Active Venues</div>
          </div>
          <div class="countries-count">
            <div class="text-4xl font-bold text-indigo-600"><%= @countries_count %>+</div>
            <div class="text-gray-600">Countries</div>
          </div>
        </div>
      </div>
      <div id={"world-map-viz-#{@id}"} class="h-[400px] w-full bg-white rounded-lg shadow-md overflow-hidden"></div>
    </div>
    """
  end

  @impl true
  def update(%{refresh_stats: true}, socket) do
    # Force refresh the statistics when explicitly requested
    stats = TriviaAdvisor.VenueStatistics.get_snapshot()

    socket =
      socket
      |> assign(:venues_by_country, stats.venues_by_country)
      |> assign(:venues_count, stats.venues_count)
      |> assign(:countries_count, stats.countries_count)
      |> assign(:stats_loaded, true)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Only fetch stats on initial load or if explicitly requested
    socket = assign(socket, :id, assigns.id)

    if socket.assigns[:stats_loaded] do
      # Stats already loaded, don't reload on every update
      {:ok, socket}
    else
      # Initial load, fetch stats once
      stats = TriviaAdvisor.VenueStatistics.get_snapshot()

      socket =
        socket
        |> assign(:venues_by_country, stats.venues_by_country)
        |> assign(:venues_count, stats.venues_count)
        |> assign(:countries_count, stats.countries_count)
        |> assign(:stats_loaded, true)

      {:ok, socket}
    end
  end
end

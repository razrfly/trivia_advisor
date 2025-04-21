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
  def update(assigns, socket) do
    venues_by_country = TriviaAdvisor.VenueStatistics.venues_by_country()
    venues_count = TriviaAdvisor.VenueStatistics.count_active_venues()
    countries_count = TriviaAdvisor.VenueStatistics.count_countries_with_venues()

    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:venues_by_country, venues_by_country)
      |> assign(:venues_count, venues_count)
      |> assign(:countries_count, countries_count)

    {:ok, socket}
  end
end

defmodule TriviaAdvisorWeb.Components.UI.CityCard do
  use TriviaAdvisorWeb, :html

  def city_card(assigns) do
    ~H"""
    <div class="relative h-64 overflow-hidden rounded-lg shadow-sm transition hover:shadow-md">
      <img
        src={@city.image_url || "https://placehold.co/600x400?text=#{@city.name}"}
        alt={@city.name}
        class="h-full w-full object-cover transition duration-300 hover:scale-105"
      />
      <div class="absolute inset-0 bg-gradient-to-b from-transparent via-black/30 to-black/60"></div>
      <div class="absolute bottom-0 w-full p-4 text-white">
        <h3 class="text-xl font-bold"><%= @city.name %></h3>
        <div class="flex items-center gap-2">
          <span class="text-sm"><%= @city.venue_count %> Venues</span>
          <span class="text-xs">•</span>
          <span class="text-sm"><%= @city.country_name %></span>
        </div>
        <a
          href={~p"/cities/#{@city.id}"}
          class="mt-2 inline-flex items-center text-sm font-medium text-white hover:underline"
        >
          Explore venues
          <svg class="ml-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M3 10a.75.75 0 01.75-.75h10.638L10.23 5.29a.75.75 0 111.04-1.08l5.5 5.25a.75.75 0 010 1.08l-5.5 5.25a.75.75 0 11-1.04-1.08l4.158-3.96H3.75A.75.75 0 013 10z" clip-rule="evenodd" />
          </svg>
        </a>
      </div>
    </div>
    """
  end
end

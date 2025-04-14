defmodule TriviaAdvisorWeb.CityLive.Components.Header do
  @moduledoc """
  Header component for city pages with hero image and title.
  """
  use TriviaAdvisorWeb, :live_component

  @doc """
  Renders the city header with hero image and attribution.

  Expected assigns:
  * city - City data including:
    * name - City name
    * country_name - Country name
    * venue_count - Number of venues
    * image_url - URL for header image
    * attribution - Map with photographer info (optional)
      * photographer_name - Name of photographer
      * photographer_url - URL to photographer profile
      * unsplash_url - URL to image on Unsplash
  """
  def render(assigns) do
    ~H"""
    <div class="relative">
      <div class="h-64 overflow-hidden sm:h-80 lg:h-96">
        <img
          src={@city.image_url || "https://placehold.co/1200x400?text=#{@city.name}"}
          alt={@city.name}
          class="h-full w-full object-cover"
        />
      </div>
      <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent"></div>
      <div class="absolute bottom-0 w-full px-4 py-8 text-white sm:px-6 lg:px-8">
        <div class="container mx-auto">
          <h1 class="text-4xl font-bold"><%= @city.name %>, <%= @city.country_name %></h1>
          <p class="mt-2 text-lg"><%= @city.venue_count %> Trivia Venues</p>
          <%= if @city.attribution do %>
            <p class="mt-1 text-xs opacity-80">
              Photo by
              <%= if Map.get(@city.attribution, "photographer_url") do %>
                <a href={Map.get(@city.attribution, :photographer_url) || Map.get(@city.attribution, "photographer_url")} target="_blank" rel="noopener" class="hover:underline">
                  <%= Map.get(@city.attribution, :photographer_name) || Map.get(@city.attribution, "photographer_name") %>
                </a>
              <% else %>
                <%= Map.get(@city.attribution, :photographer_name) || Map.get(@city.attribution, "photographer_name") %>
              <% end %>
              <%= if Map.get(@city.attribution, :unsplash_url) || Map.get(@city.attribution, "unsplash_url") do %>
                on <a href={Map.get(@city.attribution, :unsplash_url) || Map.get(@city.attribution, "unsplash_url")} target="_blank" rel="noopener" class="hover:underline">Unsplash</a>
              <% end %>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

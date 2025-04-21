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
          <p class="mt-2 text-lg"><%= @city.venue_count %> Quiz Venues</p>
          <%= if @city.attribution do %>
            <p class="mt-1 text-xs opacity-80">
              Photo by
              <%= if get_photographer_url(@city.attribution) do %>
                <a href={get_photographer_url(@city.attribution)} target="_blank" rel="noopener" class="hover:underline">
                  <%= get_photographer_name(@city.attribution) %>
                </a>
              <% else %>
                <%= get_photographer_name(@city.attribution) %>
              <% end %>
              <%= if get_unsplash_url(@city.attribution) do %>
                on <a href={get_unsplash_url(@city.attribution)} target="_blank" rel="noopener" class="hover:underline">Unsplash</a>
              <% end %>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions to get attribution data in a consistent format
  defp get_photographer_name(attribution) do
    Map.get(attribution, :photographer_name) || Map.get(attribution, "photographer_name")
  end

  defp get_photographer_url(attribution) do
    Map.get(attribution, :photographer_url) || Map.get(attribution, "photographer_url")
  end

  defp get_unsplash_url(attribution) do
    Map.get(attribution, :unsplash_url) || Map.get(attribution, "unsplash_url")
  end
end

defmodule TriviaAdvisorWeb.CityLive.Components.VenueList do
  @moduledoc """
  Component for displaying a list of venues in a grid layout.
  """
  use TriviaAdvisorWeb, :live_component

  alias TriviaAdvisorWeb.Helpers.FormatHelpers
  import FormatHelpers, only: [time_ago: 1, format_day_of_week: 1]
  import TriviaAdvisorWeb.Helpers.LocalizationHelpers, only: [format_localized_time: 2]

  require Logger

  @doc """
  Renders a grid of venue cards.

  ## Assigns
  * venues - List of venue data maps, each containing:
    * venue - The venue details
    * distance_km - Distance from the city center
  * city - City data for fallback when no venues are found
  """
  def render(assigns) do
    ~H"""
    <div>
      <%= if length(@venues) > 0 do %>
        <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <%= for venue_data <- @venues do %>
            <% venue = venue_data.venue %>
            <div class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm transition hover:shadow">
              <div class="relative h-48">
                <a href={~p"/venues/#{venue.slug}"}>
                  <img
                    src={venue.hero_image_url || get_venue_image(venue)}
                    alt={venue.name}
                    class="h-full w-full object-cover"
                  />
                </a>
                <div class="absolute right-2 top-2 rounded bg-white p-1 text-yellow-400">
                  <%= if venue.rating do %>
                    <div class="flex items-center">
                      <span class="mr-1 text-sm font-bold"><%= venue.rating %></span>
                      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                        <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118l-2.8-2.034c-.783-.57-.38-1.81.588-1.81h3.462a1 1 0 00.95-.69l1.07-3.292z" />
                      </svg>
                    </div>
                  <% else %>
                    <div class="flex items-center">
                      <span class="mr-1 text-sm font-medium text-gray-600">New</span>
                    </div>
                  <% end %>
                </div>
              </div>
              <div class="p-4">
                <a href={~p"/venues/#{venue.slug}"} class="hover:text-indigo-600">
                  <h3 class="mb-1 text-lg font-bold text-gray-900"><%= venue.name %></h3>
                </a>
                <p class="mb-2 text-sm text-gray-600">
                  <%= venue.address %>
                  <span class="mt-1 block text-xs font-medium text-indigo-600">
                    <%= Float.round(venue_data.distance_km, 1) %> km from city center
                  </span>
                </p>
                <div class="mb-3 flex items-center text-sm text-gray-600">
                  <span class="font-medium text-indigo-600"><%= format_day(get_venue_day_of_week(venue)) %>s</span>
                  <span class="mx-2">•</span>
                  <span><%= format_localized_time(get_venue_start_time(venue), get_venue_country(venue)) %></span>
                  <span class="mx-2">•</span>
                  <span><%= get_venue_entry_fee(venue) %></span>
                </div>
                <p class="mb-4 text-sm text-gray-600 line-clamp-3"><%= venue.description %></p>

                <%= if venue.last_seen_at do %>
                  <div class="flex items-center mt-2 mb-2 text-xs text-gray-500">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-1">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                    </svg>
                    <span>Updated <%= time_ago(venue.last_seen_at) %></span>
                    <%= if venue.source_name do %>
                      <span class="mx-1">•</span>
                      <span>Source:
                        <%= if venue.source_url do %>
                          <a href={venue.source_url} target="_blank" class="text-indigo-600 hover:text-indigo-800"><%= venue.source_name %></a>
                        <% else %>
                          <%= venue.source_name %>
                        <% end %>
                      </span>
                    <% end %>
                  </div>
                <% end %>

                <a
                  href={~p"/venues/#{venue.slug}"}
                  class="mt-2 inline-flex items-center text-sm font-medium text-indigo-600 hover:text-indigo-800"
                >
                  View details
                  <svg class="ml-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M3 10a.75.75 0 01.75-.75h10.638L10.23 5.29a.75.75 0 111.04-1.08l5.5 5.25a.75.75 0 010 1.08l-5.5 5.25a.75.75 0 11-1.04-1.08l4.158-3.96H3.75A.75.75 0 013 10z" clip-rule="evenodd" />
                  </svg>
                </a>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="rounded-lg border border-gray-200 bg-white p-8 text-center">
          <h3 class="mb-2 text-lg font-semibold text-gray-900">No venues found</h3>
          <p class="text-gray-600">We couldn't find any trivia venues in <%= @city.name %>.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions for venue display
  defp format_day(day) do
    format_day_of_week(day)
  end

  # Extract day of week from venue
  defp get_venue_day_of_week(venue) do
    # Get the day of week from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :day_of_week, 1) # Default to Monday if not found
    else
      # Default value if no events
      1 # Monday as default
    end
  end

  # Use the ImageHelpers module for getting venue images
  defp get_venue_image(venue) do
    TriviaAdvisorWeb.Helpers.ImageHelpers.get_venue_image(venue)
  end

  # Delegate to CityShowHelpers for these functions
  defp get_venue_start_time(venue) do
    TriviaAdvisorWeb.CityLive.Helpers.CityShowHelpers.get_venue_start_time(venue)
  end

  defp get_venue_entry_fee(venue) do
    TriviaAdvisorWeb.CityLive.Helpers.CityShowHelpers.get_venue_entry_fee(venue)
  end

  # Get country data from venue for proper localization
  defp get_venue_country(venue) do
    cond do
      # Check if venue has country_code directly (most common case based on the error)
      Map.get(venue, :country_code) ->
        %{code: venue.country_code, name: get_country_name(venue.country_code)}

      # Check if venue has city and country properly loaded
      Map.has_key?(venue, :city) &&
      venue.city &&
      !is_struct(venue.city, Ecto.Association.NotLoaded) &&
      Map.has_key?(venue.city, :country) &&
      venue.city.country &&
      !is_struct(venue.city.country, Ecto.Association.NotLoaded) ->
        venue.city.country

      # Default to US if no country data is available
      true ->
        %{code: "US", name: "United States"}
    end
  end

  # Helper to get country name from country code
  defp get_country_name("GB"), do: "United Kingdom"
  defp get_country_name("US"), do: "United States"
  defp get_country_name("AU"), do: "Australia"
  defp get_country_name("CA"), do: "Canada"
  defp get_country_name("DE"), do: "Germany"
  defp get_country_name("FR"), do: "France"
  defp get_country_name("JP"), do: "Japan"
  defp get_country_name(_), do: "Unknown"
end

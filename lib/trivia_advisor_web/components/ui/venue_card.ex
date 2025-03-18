defmodule TriviaAdvisorWeb.Components.UI.VenueCard do
  use TriviaAdvisorWeb, :html
  alias TriviaAdvisorWeb.Helpers.LocalizationHelpers

  def venue_card(assigns) do
    ~H"""
    <div class="flex flex-col overflow-hidden rounded-lg border bg-white shadow-sm transition hover:shadow-md">
      <div class="relative h-48 overflow-hidden">
        <%= if @venue.hero_image_url do %>
          <img
            src={@venue.hero_image_url}
            alt={@venue.name}
            class="h-full w-full object-cover"
          />
        <% else %>
          <div class="flex h-full w-full items-center justify-center bg-gray-200">
            <svg
              class="h-12 w-12 text-gray-400"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"
              />
            </svg>
          </div>
        <% end %>

        <!-- Entry fee badge -->
        <%= if @venue.entry_fee_cents do %>
          <div class="absolute right-2 top-2 rounded-full bg-indigo-600 px-2 py-1 text-xs font-medium text-white">
            <%= format_price(@venue.entry_fee_cents, @venue) %>
          </div>
        <% else %>
          <div class="absolute right-2 top-2 rounded-full bg-green-600 px-2 py-1 text-xs font-medium text-white">
            Free
          </div>
        <% end %>
      </div>

      <div class="flex flex-1 flex-col p-4">
        <h3 class="mb-1 text-lg font-semibold text-gray-900 line-clamp-1">
          <a href={~p"/venues/#{@venue.id}"} class="hover:text-indigo-600"><%= @venue.name %></a>
        </h3>

        <div class="mb-2 flex items-center text-sm text-gray-600">
          <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M9.69 18.933l.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 00.281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 103 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 002.273 1.765 11.842 11.842 0 00.976.544l.062.029.018.008.006.003zM10 11.25a2.25 2.25 0 100-4.5 2.25 2.25 0 000 4.5z" clip-rule="evenodd" />
          </svg>
          <span class="truncate"><%= @venue.address %></span>
        </div>

        <div class="mb-3 flex items-center text-sm text-gray-600">
          <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z" clip-rule="evenodd" />
          </svg>
          <span>
            <%= format_day(@venue.day_of_week) %> at <%= format_localized_time(@venue.start_time, get_venue_country(@venue)) %>
          </span>
        </div>

        <!-- Description with line clamp -->
        <p class="mb-4 flex-1 text-sm text-gray-600 line-clamp-3">
          <%= @venue.description %>
        </p>

        <!-- Rating stars -->
        <div class="mt-auto flex items-center">
          <div class="flex">
            <%= for i <- 1..5 do %>
              <svg
                class={"h-4 w-4 #{if i <= (@venue.rating || 0), do: "text-yellow-400", else: "text-gray-300"}"}
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
              </svg>
            <% end %>
          </div>
          <span class="ml-1 text-sm text-gray-600">
            <%= @venue.rating || "No ratings yet" %>
          </span>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions for formatting
  defp format_price(cents, venue)

  defp format_price(cents, venue) when is_integer(cents) do
    # Get the appropriate currency for this venue
    country_code = get_venue_country_code(venue)
    currency_code = get_country_currency(country_code)

    # Create Money struct with proper currency and format it
    money = Money.new(cents, currency_code)
    Money.to_string(money)
  end
  defp format_price(_, _), do: "Free"

  # Helper to get venue's country code
  defp get_venue_country_code(venue) do
    cond do
      # If venue has loaded city with country association
      is_map(venue) && Map.has_key?(venue, :city) && is_map(venue.city) &&
      Map.has_key?(venue.city, :country) && is_map(venue.city.country) &&
      Map.has_key?(venue.city.country, :code) && venue.city.country.code ->
        venue.city.country.code

      # Try to get country from metadata
      is_map(venue) && Map.has_key?(venue, :metadata) && venue.metadata &&
      is_map(venue.metadata) && Map.has_key?(venue.metadata, "country_code") ->
        venue.metadata["country_code"]

      true -> "US" # Default to US if not found
    end
  end

  # Helper to get the full country data for localization
  defp get_venue_country(venue) do
    country_code = get_venue_country_code(venue)
    %{code: country_code}
  end

  # Helper to get country's currency code
  defp get_country_currency(country_code) do
    # Try to use the Countries library to get currency code
    country_data = Countries.get(country_code)
    if country_data && Map.has_key?(country_data, :currency_code) do
      country_data.currency_code
    else
      # Just return USD as fallback
      "USD"
    end
  end

  defp format_day(day) when is_integer(day) do
    case day do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Unknown"
    end
  end

  defp format_day(_), do: "TBA"

  # Use the localization helper for time formatting
  defp format_localized_time(time, country) do
    LocalizationHelpers.format_localized_time(time, country)
  end
end

defmodule TriviaAdvisorWeb.Components.UI.VenueCard do
  use TriviaAdvisorWeb, :html
  alias TriviaAdvisorWeb.Helpers.LocalizationHelpers
  alias TriviaAdvisorWeb.Helpers.ImageHelpers

  def venue_card(assigns) do
    ~H"""
    <div class="venue-card flex flex-col overflow-hidden rounded-lg border bg-white shadow-sm transition hover:shadow-md">
      <div class="relative h-48 overflow-hidden">
        <img
          src={get_venue_image_url(assigns.venue)}
          alt={Map.get(assigns.venue, :name, "Venue")}
          class="h-full w-full object-cover"
        />

        <!-- Entry fee badge -->
        <div class="absolute right-2 top-2 rounded-full bg-indigo-600 px-2 py-1 text-xs font-medium text-white">
          <%= format_price(Map.get(assigns.venue, :entry_fee_cents), assigns.venue) %>
        </div>
      </div>

      <div class="flex flex-1 flex-col p-4">
        <h3 class="mb-1 text-lg font-semibold text-gray-900 line-clamp-1">
          <a href={~p"/venues/#{get_venue_slug(assigns.venue)}"} class="hover:text-indigo-600">
            <%= Map.get(assigns.venue, :name, "Venue") %>
          </a>
        </h3>

        <div class="mb-2 flex items-center text-sm text-gray-600">
          <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M9.69 18.933l.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 00.281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 103 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 002.273 1.765 11.842 11.842 0 00.976.544l.062.029.018.008.006.003zM10 11.25a2.25 2.25 0 100-4.5 2.25 2.25 0 000 4.5z" clip-rule="evenodd" />
          </svg>
          <span class="truncate"><%= get_venue_address(assigns.venue) %></span>
        </div>

        <div class="mb-3 flex items-center text-sm text-gray-600">
          <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z" clip-rule="evenodd" />
          </svg>
          <span>
            <%= format_day(get_venue_day_of_week(assigns.venue)) %> at <%= format_localized_time(get_venue_time(assigns.venue), get_venue_country(assigns.venue)) %>
          </span>
        </div>

        <!-- Description with line clamp -->
        <p class="mb-4 flex-1 text-sm text-gray-600 line-clamp-3">
          <%= Map.get(assigns.venue, :description, "Join us for trivia nights!") %>
        </p>

        <!-- City and Country (replacing ratings) -->
        <div class="mt-auto flex items-center">
          <svg class="mr-1 h-4 w-4 text-gray-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M1 2.75A.75.75 0 011.75 2h10.5a.75.75 0 010 1.5H12v13.75a.75.75 0 01-.75.75h-1.5a.75.75 0 01-.75-.75v-2.5h-2v2.5a.75.75 0 01-.75.75h-1.5a.75.75 0 01-.75-.75v-2.5h-2v2.5a.75.75 0 01-.75.75h-1.5a.75.75 0 01-.75-.75V3.5h-.25A.75.75 0 011 2.75zM4 5.5a.5.5 0 01.5-.5h1a.5.5 0 01.5.5v1a.5.5 0 01-.5.5h-1a.5.5 0 01-.5-.5v-1zM4.5 9a.5.5 0 00-.5.5v1a.5.5 0 00.5.5h1a.5.5 0 00.5-.5v-1a.5.5 0 00-.5-.5h-1zM8 5.5a.5.5 0 01.5-.5h1a.5.5 0 01.5.5v1a.5.5 0 01-.5.5h-1a.5.5 0 01-.5-.5v-1zM8.5 9a.5.5 0 00-.5.5v1a.5.5 0 00.5.5h1a.5.5 0 00.5-.5v-1a.5.5 0 00-.5-.5h-1zM14.25 6a.75.75 0 00-.75.75V17a1 1 0 001 1h3.75a.75.75 0 000-1.5H18v-9h.25a.75.75 0 000-1.5h-4zm.5 3.5a.5.5 0 01.5-.5h1a.5.5 0 01.5.5v1a.5.5 0 01-.5.5h-1a.5.5 0 01-.5-.5v-1zm.5 3.5a.5.5 0 00-.5.5v1a.5.5 0 00.5.5h1a.5.5 0 00.5-.5v-1a.5.5 0 00-.5-.5h-1z" clip-rule="evenodd" />
          </svg>
          <span class="text-sm text-gray-600">
            <%= display_city_and_country(assigns.venue) %>
          </span>
        </div>

        <!-- Commented out rating stars section
        <div class="mt-auto flex items-center">
          <div class="flex">
            <%= render_rating_stars(assigns.venue) %>
          </div>
          <span class="ml-1 text-sm text-gray-600">
            <%= format_rating(assigns.venue) %>
          </span>
        </div>
        -->
      </div>
    </div>
    """
  end

  # Safe helper to get venue slug or generate one from name
  defp get_venue_slug(venue) do
    slug = Map.get(venue, :slug)
    if slug && slug != "", do: slug, else: create_slug_from_name(venue)
  end

  # Create a slug from venue name
  defp create_slug_from_name(venue) do
    name = Map.get(venue, :name, "venue")
    id = Map.get(venue, :id, "unknown")

    slug = name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")

    if slug == "", do: id, else: slug
  end

  # Safe helper to get venue address
  defp get_venue_address(venue) do
    address = Map.get(venue, :address)
    city_name = if has_city?(venue), do: venue.city.name, else: nil

    cond do
      address && city_name -> "#{address}, #{city_name}"
      address -> address
      city_name -> city_name
      true -> "Location details coming soon"
    end
  end

  # Check if venue has city data
  defp has_city?(venue) do
    Map.has_key?(venue, :city) &&
    is_map(venue.city) &&
    Map.has_key?(venue.city, :name) &&
    is_binary(venue.city.name)
  end

  # Get venue day of week with fallback
  defp get_venue_day_of_week(venue) do
    cond do
      Map.has_key?(venue, :day_of_week) && venue.day_of_week ->
        venue.day_of_week

      Map.has_key?(venue, :events) &&
      !match?(%Ecto.Association.NotLoaded{}, venue.events) &&
      venue.events &&
      Enum.any?(venue.events) ->
        event = List.first(venue.events)
        Map.get(event, :day_of_week, 1)

      true ->
        1 # Default to Monday
    end
  end

  # Get venue time with fallback
  defp get_venue_time(venue) do
    cond do
      Map.has_key?(venue, :start_time) && venue.start_time && is_struct(venue.start_time, Time) ->
        venue.start_time

      Map.has_key?(venue, :start_time) && is_binary(venue.start_time) ->
        venue.start_time

      Map.has_key?(venue, :events) &&
      !match?(%Ecto.Association.NotLoaded{}, venue.events) &&
      venue.events &&
      Enum.any?(venue.events) ->
        event = List.first(venue.events)
        Map.get(event, :start_time, ~T[19:00:00])

      true ->
        ~T[19:00:00] # Default to 7:00 PM
    end
  end

  # Get venue image with fallback
  defp get_venue_image_url(venue) do
    cond do
      Map.has_key?(venue, :hero_image_url) && venue.hero_image_url && venue.hero_image_url != "" ->
        venue.hero_image_url

      true ->
        # Directly call ImageHelpers without checking if exported
        ImageHelpers.get_venue_image(venue)
    end
  end

  # Render star rating based on venue rating
  defp render_rating_stars(venue) do
    rating = get_venue_rating(venue)

    cond do
      is_nil(rating) -> "★★★★★"
      not is_number(rating) -> "★★★★★"
      true ->
        full_stars = floor(rating)
        half_star = if rating - full_stars >= 0.5, do: 1, else: 0
        empty_stars = 5 - full_stars - half_star

        full_star_html = String.duplicate("★", full_stars)
        half_star_html = if half_star == 1, do: "★", else: ""
        empty_star_html = String.duplicate("☆", empty_stars)

        full_star_html <> half_star_html <> empty_star_html
    end
  end

  # Get venue rating with fallback
  defp get_venue_rating(venue) do
    rating = Map.get(venue, :rating)

    if is_number(rating), do: rating, else: nil
  end

  # Format rating for display
  defp format_rating(venue) do
    rating = get_venue_rating(venue)

    if is_number(rating) do
      "#{:erlang.float_to_binary(rating, [decimals: 1])}"
    else
      "No ratings yet"
    end
  end

  # Helper functions for formatting
  defp format_price(cents, venue) when not is_nil(cents) do
    # Convert to integer to ensure proper handling
    cents_int =
      case cents do
        cents when is_integer(cents) -> cents
        cents when is_binary(cents) ->
          case Integer.parse(cents) do
            {int, _} -> int
            :error -> 0
          end
        _ -> 0
      end

    if cents_int > 0 do
      # Get the appropriate currency for this venue
      country_code = get_venue_country_code(venue)
      currency_code = get_country_currency(country_code)

      # Create Money struct with proper currency and format it
      money = Money.new(cents_int, currency_code)
      Money.to_string(money)
    else
      "Free"
    end
  end
  defp format_price(_, _), do: "Free"

  # Helper to get venue's country code
  defp get_venue_country_code(venue) do
    cond do
      # If venue has loaded city with country association
      has_country?(venue) ->
        venue.city.country.code

      # Try to get country from metadata
      has_metadata_country?(venue) ->
        venue.metadata["country_code"]

      true -> "GB" # Default to GB if not found
    end
  end

  # Check if venue has country data
  defp has_country?(venue) do
    is_map(venue) &&
    Map.has_key?(venue, :city) &&
    is_map(venue.city) &&
    Map.has_key?(venue.city, :country) &&
    is_map(venue.city.country) &&
    Map.has_key?(venue.city.country, :code) &&
    venue.city.country.code
  end

  # Check if venue has country in metadata
  defp has_metadata_country?(venue) do
    is_map(venue) &&
    Map.has_key?(venue, :metadata) &&
    venue.metadata &&
    is_map(venue.metadata) &&
    Map.has_key?(venue.metadata, "country_code")
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
      # Just return GBP as fallback
      "GBP"
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

  # New function to display city and country
  defp display_city_and_country(venue) do
    city_name = if has_city?(venue), do: venue.city.name, else: nil
    country_name = if has_country?(venue), do: venue.city.country.name, else: nil

    cond do
      city_name && country_name -> "#{city_name}, #{country_name}"
      city_name -> city_name
      true -> "Location TBD"
    end
  end
end

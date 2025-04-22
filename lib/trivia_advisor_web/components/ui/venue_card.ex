defmodule TriviaAdvisorWeb.Components.UI.VenueCard do
  @moduledoc """
  Component for rendering venue cards throughout the application.
  Handles consistent display of venue information with fallbacks.
  """
  use TriviaAdvisorWeb, :html
  alias TriviaAdvisorWeb.Helpers.LocalizationHelpers
  alias TriviaAdvisorWeb.Helpers.ImageHelpers

  @doc """
  Renders a venue card with all available information.
  Falls back gracefully when data is missing.
  """
  def venue_card(assigns) do
    ~H"""
    <div class="venue-card flex flex-col overflow-hidden rounded-lg border bg-white shadow-sm transition hover:shadow-md">
      <div class="relative h-48 overflow-hidden">
        <img
          src={get_venue_image_url(assigns.venue)}
          alt={Map.get(assigns.venue, :name, "Venue")}
          class="h-full w-full object-cover"
        />
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

        <div class="mb-2 flex items-center text-sm text-gray-600">
          <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z" clip-rule="evenodd" />
          </svg>
          <span>
            <%= format_day(get_venue_day_of_week(assigns.venue)) %> at <%= format_localized_time(get_venue_time(assigns.venue), get_venue_country(assigns.venue)) %>
          </span>
        </div>

        <!-- Added creation date -->
        <div class="mb-2 flex items-center text-sm text-gray-600">
          <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M5.75 2a.75.75 0 01.75.75V4h7V2.75a.75.75 0 011.5 0V4h.25A2.75 2.75 0 0118 6.75v8.5A2.75 2.75 0 0115.25 18H4.75A2.75 2.75 0 012 15.25v-8.5A2.75 2.75 0 014.75 4H5V2.75A.75.75 0 015.75 2zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75z" clip-rule="evenodd" />
          </svg>
          <span>Added <%= format_creation_date(assigns.venue) %></span>
        </div>

        <!-- Price information -->
        <div class="mb-2 flex items-center text-sm text-gray-600">
          <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path d="M10.75 10.818v2.614A3.13 3.13 0 0011.888 13c.482-.315.612-.648.612-.875 0-.227-.13-.56-.612-.875a3.13 3.13 0 00-1.138-.432zM8.33 8.62c.053.055.115.11.184.164.208.16.46.284.736.363V6.603a2.45 2.45 0 00-.35.13c-.14.065-.27.143-.386.233-.377.292-.514.627-.514.909 0 .184.058.39.202.592.037.051.08.102.128.152z" />
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-6a.75.75 0 01.75.75v.316a3.78 3.78 0 011.653.713c.426.33.744.74.925 1.2a.75.75 0 01-1.395.55 1.35 1.35 0 00-.447-.563 2.187 2.187 0 00-.736-.363V9.3c.698.093 1.383.32 1.959.696.787.514 1.29 1.27 1.29 2.13 0 .86-.504 1.616-1.29 2.13-.576.377-1.261.603-1.96.696v.299a.75.75 0 11-1.5 0v-.3c-.697-.092-1.382-.318-1.958-.695-.482-.315-.857-.717-1.078-1.188a.75.75 0 111.359-.636c.08.173.245.376.54.569.313.205.706.353 1.138.432v-2.748a3.782 3.782 0 01-1.653-.713C6.9 9.433 6.5 8.681 6.5 7.875c0-.805.4-1.558 1.097-2.096a3.78 3.78 0 011.653-.713V4.75A.75.75 0 0110 4z" clip-rule="evenodd" />
          </svg>
          <span>
            <%= display_formatted_price(assigns.venue) %>
          </span>
        </div>

        <!-- Description with line clamp -->
        <p class="mb-4 flex-1 text-sm text-gray-600 line-clamp-3">
          <%= get_venue_description(assigns.venue) %>
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

  # -- VENUE DATA HELPERS --

  # Gets the venue slug or generates one from the name if not available.
  @spec get_venue_slug(map()) :: String.t()
  defp get_venue_slug(venue) do
    slug = Map.get(venue, :slug)
    if is_binary(slug) && slug != "", do: slug, else: create_slug_from_name(venue)
  end

  # Creates a URL-friendly slug from the venue name.
  @spec create_slug_from_name(map()) :: String.t()
  defp create_slug_from_name(venue) do
    name = Map.get(venue, :name, "venue")
    id = Map.get(venue, :id, "unknown")

    slug = name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")

    if slug == "", do: id, else: slug
  end

  # Gets the formatted venue address, combining address and city when available.
  @spec get_venue_address(map()) :: String.t()
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

  # Gets the venue day of week with appropriate fallbacks.
  @spec get_venue_day_of_week(map()) :: integer()
  defp get_venue_day_of_week(venue) do
    cond do
      # Directly on venue
      Map.has_key?(venue, :day_of_week) && venue.day_of_week ->
        venue.day_of_week

      # From first event
      has_loaded_events?(venue) ->
        event = List.first(venue.events)
        Map.get(event, :day_of_week, 1)

      # Default
      true ->
        1 # Default to Monday
    end
  end

  # Gets the venue start time with appropriate fallbacks.
  @spec get_venue_time(map()) :: Time.t() | String.t()
  defp get_venue_time(venue) do
    cond do
      # Time struct directly on venue
      Map.has_key?(venue, :start_time) && venue.start_time && is_struct(venue.start_time, Time) ->
        venue.start_time

      # String time on venue
      Map.has_key?(venue, :start_time) && is_binary(venue.start_time) ->
        venue.start_time

      # Time from first event
      has_loaded_events?(venue) ->
        event = List.first(venue.events)
        Map.get(event, :start_time, ~T[19:00:00])

      # Default
      true ->
        ~T[19:00:00] # Default to 7:00 PM
    end
  end

  # Gets the venue image URL with fallback to ImageHelpers.
  @spec get_venue_image_url(map()) :: String.t()
  defp get_venue_image_url(venue) do
    cond do
      # Hero image URL directly on venue
      Map.has_key?(venue, :hero_image_url) && is_binary(venue.hero_image_url) && venue.hero_image_url != "" ->
        venue.hero_image_url

      # Use ImageHelpers fallback
      true ->
        ImageHelpers.get_venue_image(venue)
    end
  end

  # Gets the venue description, falling back to event description or a default.
  @spec get_venue_description(map()) :: String.t()
  defp get_venue_description(venue) do
    venue_description = Map.get(venue, :description)

    cond do
      # Use venue description if available
      is_binary(venue_description) && venue_description != "" ->
        venue_description

      # Try to get description from first event
      has_loaded_events?(venue) ->
        event = List.first(venue.events)
        event_description = Map.get(event, :description)

        if is_binary(event_description) && event_description != "",
          do: event_description,
          else: default_description(venue)

      # Default fallback
      true ->
        default_description(venue)
    end
  end

  # Creates a default description using the venue name.
  @spec default_description(map()) :: String.t()
  defp default_description(venue) do
    "Join us for trivia nights at #{Map.get(venue, :name, "this venue")}!"
  end

  # -- FORMATTING HELPERS --

  # Renders star rating based on venue rating with defaults.
  @spec render_rating_stars(map()) :: String.t()
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

  # Gets venue rating value with type checking.
  @spec get_venue_rating(map()) :: float() | nil
  defp get_venue_rating(venue) do
    rating = Map.get(venue, :rating)
    if is_number(rating), do: rating, else: nil
  end

  # Formats rating as a string for display.
  @spec format_rating(map()) :: String.t()
  defp format_rating(venue) do
    rating = get_venue_rating(venue)

    if is_number(rating) do
      "#{:erlang.float_to_binary(rating, [decimals: 1])}"
    else
      "No ratings yet"
    end
  end

  # Displays formatted price with proper currency based on venue's country.
  @spec display_formatted_price(map()) :: String.t()
  defp display_formatted_price(venue) do
    # Find the entry fee based on priority order
    entry_fee_cents = get_entry_fee_cents(venue)

    cond do
      # No fee or zero fee
      is_nil(entry_fee_cents) ||
      (is_binary(entry_fee_cents) && entry_fee_cents == "") ->
        "Free Entry"

      # Convert and format fee
      true ->
        cents_int = normalize_cents(entry_fee_cents)

        if cents_int <= 0 do
          "Free Entry"
        else
          # Get the appropriate currency for this venue
          country_code = get_venue_country_code(venue)
          currency_code = get_country_currency(country_code)

          # Create Money struct with proper currency and format it
          money = Money.new(cents_int, currency_code)
          "Entry: #{Money.to_string(money)}"
        end
    end
  end

  # Gets the entry fee amount in cents with fallbacks.
  @spec get_entry_fee_cents(map()) :: integer() | nil
  defp get_entry_fee_cents(venue) do
    venue_fee = Map.get(venue, :entry_fee_cents)

    event_fee =
      if has_loaded_events?(venue) do
        event = List.first(venue.events)
        Map.get(event, :entry_fee_cents)
      else
        nil
      end

    # Use the most appropriate fee
    cond do
      is_integer(venue_fee) && venue_fee > 0 -> venue_fee
      is_integer(event_fee) && event_fee > 0 -> event_fee
      true -> nil
    end
  end

  # Normalizes various formats of cents into a consistent integer.
  @spec normalize_cents(any()) :: integer() | nil
  defp normalize_cents(cents) do
    case cents do
      cents when is_integer(cents) -> cents
      cents when is_binary(cents) ->
        case Integer.parse(cents) do
          {int, _} -> int
          :error -> 0
        end
      _ -> 0
    end
  end

  # Gets the venue's country code with fallbacks.
  @spec get_venue_country_code(map()) :: String.t() | nil
  defp get_venue_country_code(venue) do
    cond do
      # From city.country association
      has_country?(venue) ->
        venue.city.country.code

      # From metadata
      has_metadata_country?(venue) ->
        venue.metadata["country_code"]

      # Default
      true -> "GB" # Default to GB if not found
    end
  end

  # Gets the venue's country with appropriate fallbacks.
  @spec get_venue_country(map()) :: map() | nil
  defp get_venue_country(venue) do
    country_code = get_venue_country_code(venue)
    %{code: country_code}
  end

  # Gets the currency for a country based on country code.
  @spec get_country_currency(String.t()) :: String.t()
  defp get_country_currency(country_code) do
    currency_code =
      case Countries.get(country_code) do
        nil ->
          # Country not found, use default
          "GBP"
        country_data when is_map(country_data) ->
          if Map.has_key?(country_data, :currency_code) &&
             is_binary(country_data.currency_code) &&
             country_data.currency_code != "" do
            country_data.currency_code
          else
            # No currency code or invalid one, use default
            "GBP"
          end
        _ ->
          # Any other unexpected result, use default
          "GBP"
      end

    # Verify the currency is valid for the Money library
    # Use a safe approach with try/rescue
    try do
      # This will raise an error if the currency doesn't exist
      # We're not actually using the result, just validating the currency
      Money.new(0, currency_code)
      currency_code
    rescue
      _ ->
        # If any error occurs with the currency, fall back to GBP
        "GBP"
    end
  end

  # Formats a day of week integer into a readable string.
  @spec format_day(integer()) :: String.t()
  defp format_day(day_of_week) do
    case day_of_week do
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

  # Formats a time for the specified time zone.
  @spec format_localized_time(Time.t() | String.t(), String.t()) :: String.t()
  defp format_localized_time(time, timezone) do
    LocalizationHelpers.format_localized_time(time, timezone)
  end

  # Displays city and country names with appropriate formatting.
  @spec display_city_and_country(map()) :: String.t()
  defp display_city_and_country(venue) do
    city_name = if has_city?(venue), do: venue.city.name, else: nil
    country_name = if has_country?(venue), do: venue.city.country.name, else: nil

    cond do
      city_name && country_name -> "#{city_name}, #{country_name}"
      city_name -> city_name
      true -> "Location TBD"
    end
  end

  # Checks if the venue has a valid city association.
  @spec has_city?(map()) :: boolean()
  defp has_city?(venue) do
    is_map(venue) &&
    Map.has_key?(venue, :city) &&
    is_map(venue.city) &&
    Map.has_key?(venue.city, :name) &&
    is_binary(venue.city.name)
  end

  # Checks if the venue has a valid country association.
  @spec has_country?(map()) :: boolean()
  defp has_country?(venue) do
    has_city?(venue) &&
    Map.has_key?(venue.city, :country) &&
    is_map(venue.city.country) &&
    Map.has_key?(venue.city.country, :code) &&
    is_binary(venue.city.country.code)
  end

  # Checks if the venue has country info in metadata.
  @spec has_metadata_country?(map()) :: boolean()
  defp has_metadata_country?(venue) do
    is_map(venue) &&
    Map.has_key?(venue, :metadata) &&
    is_map(venue.metadata) &&
    Map.has_key?(venue.metadata, "country_code") &&
    is_binary(venue.metadata["country_code"])
  end

  # Checks if the venue has preloaded events.
  @spec has_loaded_events?(map()) :: boolean()
  defp has_loaded_events?(venue) do
    is_map(venue) &&
    Map.has_key?(venue, :events) &&
    !match?(%Ecto.Association.NotLoaded{}, venue.events) &&
    is_list(venue.events) &&
    length(venue.events) > 0
  end

  # Format creation date using the time_ago_in_words helper
  @spec format_creation_date(map()) :: String.t()
  defp format_creation_date(venue) do
    inserted_at = Map.get(venue, :inserted_at)

    if inserted_at do
      TriviaAdvisorWeb.Helpers.FormatHelpers.time_ago_in_words(inserted_at)
    else
      "recently"
    end
  end
end

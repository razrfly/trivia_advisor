defmodule TriviaAdvisorWeb.CityLive.Helpers.CityShowHelpers do
  @moduledoc """
  Helper functions specific to the City Show LiveView.
  """
  alias TriviaAdvisor.Locations
  alias TriviaAdvisorWeb.Helpers.CurrencyHelpers
  alias TriviaAdvisorWeb.Helpers.ImageHelpers
  require Logger

  @doc """
  Get city data using either the database or mock data.
  Returns an :ok/:error tuple with formatted city data.
  """
  def get_city_data(slug) do
    # Try to get the city from the database first
    case Locations.get_city_by_slug(slug) do
      %{} = city ->
        # If found, format the data for display
        # Use count_venues_with_events_near_city to only count venues with events
        venues_count = Locations.count_venues_with_events_near_city(city, radius_km: 50)

        # Get the image data from the city's unsplash_gallery
        {image_url, attribution} = ImageHelpers.get_city_image_with_attribution(city)

        {:ok, %{
          id: city.id,
          name: city.name,
          slug: city.slug,
          country_name: city.country.name,
          venue_count: venues_count,
          image_url: image_url,
          attribution: attribution,
          city: city
        }}

      nil ->
        # If not found in database, try mock data
        case get_mock_city_by_slug(slug) do
          nil -> {:error, :not_found}
          city_data -> {:ok, city_data}
        end
    end
  end

  @doc """
  Get venues near a city using spatial search.
  Returns a list of formatted venue data with distances.
  """
  def get_venues_near_city(city, radius) do
    try do
      # Get venues near the city within the specified radius
      results = Locations.find_venues_near_city(city, radius_km: radius, load_relations: true)

      # Filter out venues without events
      results_with_events = Enum.filter(results, fn %{venue: venue} ->
        venue.events && Enum.any?(venue.events)
      end)

      # Format the venue data for display
      Enum.map(results_with_events, fn %{venue: venue, distance_km: distance} ->
        try do
          # Extract event source data if available
          event_source_data = get_event_source_data(venue)

          # Ensure we have country data for currency detection
          venue_with_country = ensure_country_data(venue, city)

          %{
            venue: %{
              id: venue.id,
              name: venue.name,
              slug: venue.slug,
              address: venue.address,
              description: get_venue_description(venue),
              hero_image_url: ImageHelpers.get_venue_image(venue),
              rating: get_venue_rating(venue),
              events: Map.get(venue, :events, []),
              last_seen_at: event_source_data[:last_seen_at],
              source_name: event_source_data[:source_name],
              source_url: event_source_data[:source_url],
              # Add country_code to venue for currency detection
              country_code: CurrencyHelpers.get_country(venue_with_country).code
            },
            distance_km: distance
          }
        rescue
          e ->
            Logger.error("Error processing venue data: #{inspect(e)}")
            # Return a simplified venue object with just the essential data
            %{
              venue: %{
                id: venue.id,
                name: venue.name,
                slug: venue.slug,
                address: venue.address || "No address available",
                description: "Information for this venue is temporarily unavailable.",
                hero_image_url: "/images/default-venue.jpg",
                rating: 4.0,
                events: [],
                last_seen_at: nil,
                source_name: nil,
                source_url: nil,
                # Add country_code from the parent city for proper currency formatting
                country_code: city.country.code
              },
              distance_km: distance
            }
        end
      end)
    rescue
      e ->
        Logger.error("Error fetching venues for city: #{inspect(e)}")
        # Return empty list on error
        []
    end
  end

  @doc """
  Get suburbs (nearby cities) with venue counts.
  """
  def get_suburbs(city) do
    try do
      Locations.find_suburbs_near_city(city, radius_km: 50, limit: 10)
    rescue
      e ->
        Logger.error("Error fetching suburbs for city: #{inspect(e)}")
        []
    end
  end

  @doc """
  Filter venues based on selected suburbs.
  """
  def filter_venues_by_suburbs(city, radius, selected_suburb_ids, suburbs) do
    # Extract suburb city objects from the suburbs list
    selected_suburbs = suburbs
      |> Enum.filter(fn suburb -> suburb.city.id in selected_suburb_ids end)
      |> Enum.map(fn suburb -> suburb.city end)

    try do
      # Get venues near each selected suburb and combine them
      venues = Enum.flat_map(selected_suburbs, fn suburb ->
        Locations.find_venues_near_city(suburb, radius_km: radius, load_relations: true)
      end)

      # Filter out venues without events
      venues_with_events = Enum.filter(venues, fn %{venue: venue} ->
        venue.events && Enum.any?(venue.events)
      end)

      # Format venue data for display
      Enum.map(venues_with_events, fn %{venue: venue, distance_km: distance} ->
        try do
          # Extract event source data if available
          event_source_data = get_event_source_data(venue)

          # Ensure we have country data for currency detection
          venue_with_country = ensure_country_data(venue, city)

          %{
            venue: %{
              id: venue.id,
              name: venue.name,
              slug: venue.slug,
              address: venue.address,
              description: get_venue_description(venue),
              hero_image_url: ImageHelpers.get_venue_image(venue),
              rating: get_venue_rating(venue),
              events: Map.get(venue, :events, []),
              last_seen_at: event_source_data[:last_seen_at],
              source_name: event_source_data[:source_name],
              source_url: event_source_data[:source_url],
              country_code: CurrencyHelpers.get_country(venue_with_country).code
            },
            distance_km: distance
          }
        rescue
          e ->
            Logger.error("Error processing venue data: #{inspect(e)}")
            %{
              venue: %{
                id: venue.id,
                name: venue.name,
                slug: venue.slug,
                address: venue.address || "No address available",
                description: "Information unavailable",
                hero_image_url: "/images/default-venue.jpg",
                rating: 4.0,
                events: [],
                last_seen_at: nil,
                source_name: nil,
                source_url: nil,
                country_code: city.country.code
              },
              distance_km: distance
            }
        end
      end)
    rescue
      e ->
        Logger.error("Error filtering venues by suburbs: #{inspect(e)}")
        []
    end
  end

  @doc """
  Extract venue's start time from its events.
  """
  def get_venue_start_time(venue) do
    # Get the start time from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :start_time, "7:00 PM")
    else
      # Default value if no events
      "7:00 PM"
    end
  end

  @doc """
  Extract venue's entry fee from its events and format as currency.
  """
  def get_venue_entry_fee(venue) do
    # Get the entry fee from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      fee_cents = Map.get(event, :entry_fee_cents)

      if fee_cents do
        # Format the currency using CurrencyHelpers
        currency_code = CurrencyHelpers.get_country_currency(venue)
        CurrencyHelpers.format_currency(fee_cents, currency_code)
      else
        # Free if no fee specified
        "Free"
      end
    else
      # Default value if no events
      "Free"
    end
  end

  @doc """
  Extract event source data from a venue.
  """
  def get_event_source_data(venue) do
    cond do
      venue.events && Enum.any?(venue.events) ->
        event = List.first(venue.events)
        if event.event_sources && Enum.any?(event.event_sources) do
          event_source = List.first(event.event_sources)
          source_name = if event_source.source do
            event_source.source.name
          else
            nil
          end

          %{
            last_seen_at: event_source.last_seen_at || event.last_seen_at || event.inserted_at,
            source_name: source_name,
            source_url: event_source.source_url
          }
        else
          %{
            last_seen_at: event.last_seen_at || event.inserted_at,
            source_name: event.source_name,
            source_url: event.source_url
          }
        end
      true ->
        %{
          last_seen_at: venue.last_seen_at || venue.inserted_at,
          source_name: venue.source_name,
          source_url: venue.source_url
        }
    end
  end

  @doc """
  Extract description from venue data.
  """
  def get_venue_description(venue) do
    # First try to get description from events
    event_description = if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :description)
    end

    # Use direct description if available, then try event description, then metadata, then fallback to generic
    event_description ||
    Map.get(venue, :description) ||
    (if Map.has_key?(venue, :metadata), do: venue.metadata["description"]) ||
    "A trivia night at #{venue.name}. Join us for a fun evening of questions, prizes, and drinks."
  end

  @doc """
  Extract rating from venue data.
  """
  def get_venue_rating(venue) do
    # Check for direct rating first, then metadata rating
    cond do
      # Direct rating on venue object
      is_number(Map.get(venue, :rating)) ->
        venue.rating

      # In metadata if it exists
      Map.has_key?(venue, :metadata) ->
        case venue.metadata["rating"] do
          nil ->
            # Generate random rating if not available
            (3.5 + :rand.uniform() * 1.5) |> Float.round(1)
          rating when is_number(rating) ->
            # Use the rating directly if it's a number
            rating
          %{"value" => value} when is_number(value) ->
            # Extract the value from map if it's in that format
            value
          _ ->
            # Fallback for any other format
            (3.5 + :rand.uniform() * 1.5) |> Float.round(1)
        end

      # No rating info available - generate random
      true ->
        (3.5 + :rand.uniform() * 1.5) |> Float.round(1)
    end
  end

  @doc """
  Ensure country data is available on venue.
  """
  def ensure_country_data(venue, city) do
    if (venue.city && !is_struct(venue.city, Ecto.Association.NotLoaded) &&
       venue.city.country && !is_struct(venue.city.country, Ecto.Association.NotLoaded)) do
      venue
    else
      Map.put(venue, :city, Map.put(city, :country, city.country))
    end
  end

  # Get mock city data by slug (for development only)
  defp get_mock_city_by_slug(slug) do
    mock_cities = [
      %{
        id: "1",
        name: "London",
        slug: "london",
        country_name: "United Kingdom",
        venue_count: 120,
        image_url: "https://images.unsplash.com/photo-1533929736458-ca588d08c8be?q=80&w=2000",
        attribution: %{
          "photographer_name" => "Benjamin Davies",
          "photographer_url" => "https://unsplash.com/@bendavisual",
          "unsplash_url" => "https://unsplash.com/photos/Oja2ty_9ZLM"
        }
      },
      %{
        id: "2",
        name: "New York",
        slug: "new-york",
        country_name: "United States",
        venue_count: 85,
        image_url: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?q=80&w=2000",
        attribution: %{
          "photographer_name" => "Andres Iga",
          "photographer_url" => "https://unsplash.com/@andresiga",
          "unsplash_url" => "https://unsplash.com/photos/7XKkJVw1d8c"
        }
      }
    ]

    Enum.find(mock_cities, fn city -> city.slug == slug end)
  end
end

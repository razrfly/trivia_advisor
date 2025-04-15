defmodule TriviaAdvisor.Locations do
  @moduledoc """
  The Locations context.
  """

  import Ecto.Query, warn: false
  alias TriviaAdvisor.Repo

  alias TriviaAdvisor.Locations.Country

  @doc """
  Returns the list of countries.

  ## Examples

      iex> list_countries()
      [%Country{}, ...]

  """
  def list_countries do
    Repo.all(Country)
  end

  @doc """
  Gets a single country.

  Raises `Ecto.NoResultsError` if the Country does not exist.

  ## Examples

      iex> get_country!(123)
      %Country{}

      iex> get_country!(456)
      ** (Ecto.NoResultsError)

  """
  def get_country!(id), do: Repo.get!(Country, id)

  @doc """
  Creates a country.

  ## Examples

      iex> create_country(%{field: value})
      {:ok, %Country{}}

      iex> create_country(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_country(attrs \\ %{}) do
    %Country{}
    |> Country.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a country.

  ## Examples

      iex> update_country(country, %{field: new_value})
      {:ok, %Country{}}

      iex> update_country(country, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_country(%Country{} = country, attrs) do
    country
    |> Country.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a country.

  ## Examples

      iex> delete_country(country)
      {:ok, %Country{}}

      iex> delete_country(country)
      {:error, %Ecto.Changeset{}}

  """
  def delete_country(%Country{} = country) do
    Repo.delete_with_callbacks(country)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking country changes.

  ## Examples

      iex> change_country(country)
      %Ecto.Changeset{data: %Country{}}

  """
  def change_country(%Country{} = country, attrs \\ %{}) do
    Country.changeset(country, attrs)
  end

  alias TriviaAdvisor.Locations.City

  @doc """
  Returns the list of cities.

  ## Examples

      iex> list_cities()
      [%City{}, ...]

  """
  def list_cities do
    Repo.all(City)
  end

  @doc """
  Gets a single city.

  Raises `Ecto.NoResultsError` if the City does not exist.

  ## Examples

      iex> get_city!(123)
      %City{}

      iex> get_city!(456)
      ** (Ecto.NoResultsError)

  """
  def get_city!(id), do: Repo.get!(City, id)

  @doc """
  Gets a single city by slug.

  Returns nil if no city exists with the given slug.

  ## Examples

      iex> get_city_by_slug("london")
      %City{}

      iex> get_city_by_slug("nonexistent-city")
      nil

  """
  def get_city_by_slug(slug) when is_binary(slug) do
    Repo.get_by(City, slug: slug)
    |> Repo.preload(:country)
  end

  @doc """
  Gets a single country by slug.

  Returns nil if no country exists with the given slug.

  ## Examples

      iex> get_country_by_slug("united-kingdom")
      %Country{}

      iex> get_country_by_slug("nonexistent-country")
      nil
  """
  def get_country_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Country, slug: slug)
  end

  @doc """
  Counts the number of venues for a specific city.

  ## Examples

      iex> count_venues_by_city_id(123)
      5

  """
  def count_venues_by_city_id(city_id) do
    query = from v in TriviaAdvisor.Locations.Venue,
            where: v.city_id == ^city_id,
            select: count(v.id)

    Repo.one(query) || 0
  end

  @doc """
  Creates a city.

  ## Examples

      iex> create_city(%{field: value})
      {:ok, %City{}}

      iex> create_city(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_city(attrs \\ %{}) do
    %City{}
    |> City.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a city.

  ## Examples

      iex> update_city(city, %{field: new_value})
      {:ok, %City{}}

      iex> update_city(city, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_city(%City{} = city, attrs) do
    city
    |> City.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a city.

  ## Examples

      iex> delete_city(city)
      {:ok, %City{}}

      iex> delete_city(city)
      {:error, %Ecto.Changeset{}}

  """
  def delete_city(%City{} = city) do
    Repo.delete_with_callbacks(city)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking city changes.

  ## Examples

      iex> change_city(city)
      %Ecto.Changeset{data: %City{}}

  """
  def change_city(%City{} = city, attrs \\ %{}) do
    City.changeset(city, attrs)
  end

  alias TriviaAdvisor.Locations.Venue

  @doc """
  Returns the list of venues.

  ## Examples

      iex> list_venues()
      [%Venue{}, ...]

  """
  def list_venues do
    Repo.all(Venue)
  end

  @doc """
  Gets a single venue.

  Raises `Ecto.NoResultsError` if the Venue does not exist.

  ## Examples

      iex> get_venue!(123)
      %Venue{}

      iex> get_venue!(456)
      ** (Ecto.NoResultsError)

  """
  def get_venue!(id), do: Repo.get!(Venue, id)

  @doc """
  Gets a single venue by slug.

  Returns nil if no venue exists with the given slug.

  ## Examples

      iex> get_venue_by_slug("some-venue-slug")
      %Venue{}

      iex> get_venue_by_slug("nonexistent-venue")
      nil

  """
  def get_venue_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Venue, slug: slug)
  end

  @doc """
  Creates a venue.

  ## Examples

      iex> create_venue(%{field: value})
      {:ok, %Venue{}}

      iex> create_venue(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_venue(attrs \\ %{}) do
    %Venue{}
    |> Venue.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a venue.

  ## Examples

      iex> update_venue(venue, %{field: new_value})
      {:ok, %Venue{}}

      iex> update_venue(venue, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_venue(%Venue{} = venue, attrs) do
    changeset = venue
    |> Venue.changeset(attrs)

    result = Repo.update(changeset)

    case result do
      {:ok, updated_venue} ->
        # Call after_update callback to handle image cleanup if needed
        Venue.after_update(changeset)
        {:ok, updated_venue}
      error -> error
    end
  end

  @doc """
  Deletes a venue.

  ## Examples

      iex> delete_venue(venue)
      {:ok, %Venue{}}

      iex> delete_venue(venue)
      {:error, %Ecto.Changeset{}}

  """
  def delete_venue(%Venue{} = venue) do
    # Call before_delete callback to handle image cleanup
    venue
    |> Venue.before_delete()
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking venue changes.

  ## Examples

      iex> change_venue(venue)
      %Ecto.Changeset{data: %Venue{}}

  """
  def change_venue(%Venue{} = venue, attrs \\ %{}) do
    Venue.changeset(venue, attrs)
  end

  def find_or_create_country(country_code) do
    case Repo.get_by(Country, code: country_code) do
      nil ->
        try do
          case Countries.get(country_code) do
            [] -> {:error, "Invalid country code"}
            country_data ->
              %Country{}
              |> Country.changeset(%{
                code: country_data.alpha2,
                name: country_data.name
              })
              |> Repo.insert()
          end
        rescue
          _ -> {:error, "Invalid country code"}
        end
      country -> {:ok, country}
    end
  end

  def find_or_create_city(city_name, country_code) when is_binary(city_name) and is_binary(country_code) do
    normalized_name = city_name |> String.trim() |> String.replace(~r/\s+/, " ")
    base_slug = normalized_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

    with {:ok, country} <- find_or_create_country(country_code) do
      country_specific_slug = "#{base_slug}-#{String.downcase(country.code)}"

      # First try to find by case-insensitive name and country_id
      import Ecto.Query
      case Repo.one(
        from c in City,
        where: fragment("LOWER(?)", c.name) == ^String.downcase(normalized_name)
          and c.country_id == ^country.id,
        limit: 1
      ) do
        %City{} = city ->
          {:ok, city}

        nil ->
          %City{}
          |> City.changeset(%{
            name: normalized_name,
            country_id: country.id,
            slug: country_specific_slug
          })
          |> Repo.insert()
      end
    end
  end

  @doc """
  Finds or creates a venue based on provided details.
  Uses Google Places API for geocoding and deduplication.
  """
  @spec find_or_create_venue(map()) :: {:ok, Venue.t()} | {:error, String.t()}
  def find_or_create_venue(%{"address" => _} = attrs), do: do_find_or_create_venue(attrs)
  def find_or_create_venue(_), do: {:error, "Address is required"}

  defp do_find_or_create_venue(%{"address" => address} = attrs) do
    google_lookup = Application.get_env(:trivia_advisor, :google_lookup, TriviaAdvisor.Scraping.GoogleLookup)

    with {:ok, location_data} <- google_lookup.lookup_address(address),
         {:ok, validated_data} <- validate_location_data(location_data),
         {:ok, country} <- find_or_create_country(validated_data.country_code),
         {:ok, city} <- find_or_create_city(normalize_city_name(validated_data.city), country.code) do

      lat = Decimal.new(to_string(validated_data.lat))
      lng = Decimal.new(to_string(validated_data.lng))

      # Try to find existing venue in this order:
      # 1. By place_id (exact match)
      # 2. By coordinates within 100m radius in same city
      # 3. Create new if none found
      existing_venue =
        if validated_data.place_id do
          # First try by place_id
          Repo.get_by(Venue, place_id: validated_data.place_id)
        end

      # Then try by proximity if no venue found by place_id
      existing_venue =
        if is_nil(existing_venue) do
          lat_float = Decimal.to_float(lat)
          lng_float = Decimal.to_float(lng)

          # Find venues within roughly 100m using coordinate comparison
          # 0.001 degrees ≈ 111m at the equator
          Repo.one(
            from v in Venue,
            where: v.city_id == ^city.id
              and fragment(
                "ABS(CAST(? AS FLOAT) - CAST(latitude AS FLOAT)) < 0.001 AND ABS(CAST(? AS FLOAT) - CAST(longitude AS FLOAT)) < 0.001",
                type(^lat_float, :float),
                type(^lng_float, :float)
              ),
            limit: 1
          )
        else
          existing_venue
        end

      case existing_venue do
        nil -> create_venue(attrs, validated_data, city)
        venue -> {:ok, venue}
      end
    end
  end

  defp validate_location_data(%{lat: lat, lng: lng} = data)
    when is_number(lat) and is_number(lng) and lat >= -90 and lat <= 90
    and lng >= -180 and lng <= 180 do
    case {Map.get(data, :city), Map.get(data, :country_code)} do
      {nil, _} -> {:error, "City name missing"}
      {_, nil} -> {:error, "Country code missing"}
      {city, code} when is_binary(city) and is_binary(code) -> {:ok, data}
      _ -> {:error, "Invalid city or country data"}
    end
  end
  defp validate_location_data(_), do: {:error, "Invalid or missing coordinates"}

  defp normalize_city_name(city) when is_binary(city) do
    city
    |> String.replace(~r/\s*\(.+\)$/, "")  # Remove parenthetical content
    |> String.replace(~r/\s*,.+$/, "")     # Remove everything after comma
    |> String.trim()
  end

  defp create_venue(attrs, validated_data, city) do
    metadata = extract_relevant_metadata(validated_data)

    %Venue{}
    |> Venue.changeset(%{
      name: attrs["title"],
      address: attrs["address"],
      postcode: validated_data.postcode,
      latitude: Decimal.new(to_string(validated_data.lat)),
      longitude: Decimal.new(to_string(validated_data.lng)),
      place_id: validated_data.place_id,
      phone: attrs["phone"],
      website: attrs["website"],
      city_id: city.id,
      metadata: metadata
    })
    |> Repo.insert()
  end

  defp extract_relevant_metadata(google_data) do
    %{
      "formatted_address" => Map.get(google_data, "formatted_address"),
      "place_id" => Map.get(google_data, "place_id"),
      "address_components" => extract_address_components(Map.get(google_data, "address_components", [])),
      "business_status" => Map.get(google_data, "business_status"),
      "formatted_phone_number" => Map.get(google_data, "formatted_phone_number"),
      "international_phone_number" => Map.get(google_data, "international_phone_number"),
      "opening_hours" => Map.get(google_data, "opening_hours"),
      "rating" => Map.get(google_data, "rating"),
      "user_ratings_total" => Map.get(google_data, "user_ratings_total")
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp extract_address_components(components) do
    Enum.reduce(components, %{}, fn component, acc ->
      type = List.first(Map.get(component, "types", []))
      if type do
        Map.put(acc, type, %{
          "long_name" => Map.get(component, "long_name"),
          "short_name" => Map.get(component, "short_name")
        })
      else
        acc
      end
    end)
  end

  @doc """
  Lists all venues for a specific city.

  ## Examples

      iex> list_venues_by_city_id(123)
      [%Venue{}, ...]

  """
  def list_venues_by_city_id(city_id) do
    Venue
    |> where([v], v.city_id == ^city_id)
    |> preload(:city)
    |> Repo.all()
  end

  @doc """
  Find venues near a city within a specified radius.
  Uses PostGIS to calculate distances.

  ## Options
    * `:radius_km` - search radius in kilometers (default: 50)
    * `:limit` - maximum number of venues to return (default: 100)
    * `:load_relations` - whether to preload relations (default: true)

  ## Examples

      iex> find_venues_near_city(city, radius_km: 25)
      [%{venue: %Venue{}, distance_km: 12.5}, ...]

  """
  def find_venues_near_city(%City{} = city, opts \\ []) do
    find_venues_near_coordinates(City.coordinates(city), opts)
  end

  @doc """
  Find venues near specific coordinates within a specified radius.
  Uses PostGIS to calculate distances.

  ## Options
    * `:radius_km` - search radius in kilometers (default: 50)
    * `:limit` - maximum number of venues to return (default: 100)
    * `:load_relations` - whether to preload relations (default: true)

  ## Examples

      iex> find_venues_near_coordinates({-37.8136, 144.9631}, radius_km: 25)
      [%{venue: %Venue{}, distance_km: 12.5}, ...]

  """
  def find_venues_near_coordinates({lat, lng}, opts \\ []) when is_number(lat) and is_number(lng) do
    radius_km = Keyword.get(opts, :radius_km, 50)
    limit = Keyword.get(opts, :limit, 100)
    load_relations = Keyword.get(opts, :load_relations, true)

    # Apply preloads first if requested
    venue_query = if load_relations do
      from v in Venue, preload: [
        :city,
        events: [
          :performer,
          event_sources: [:source]
        ]
      ]
    else
      Venue
    end

    # PostGIS query using ST_DWithin for efficient distance filtering
    query = from v in venue_query,
      select: %{
        venue: v,
        distance_km: fragment(
          "ST_Distance(
            ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
            ST_SetSRID(ST_MakePoint(CAST(? AS FLOAT), CAST(? AS FLOAT)), 4326)::geography
          ) / 1000.0",
          ^lng, ^lat, v.longitude, v.latitude
        )
      },
      where: fragment(
        "ST_DWithin(
          ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
          ST_SetSRID(ST_MakePoint(CAST(? AS FLOAT), CAST(? AS FLOAT)), 4326)::geography,
          ?
        )",
        ^lng, ^lat, v.longitude, v.latitude, ^(radius_km * 1000)
      ),
      order_by: fragment(
        "ST_Distance(
          ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
          ST_SetSRID(ST_MakePoint(CAST(? AS FLOAT), CAST(? AS FLOAT)), 4326)::geography
        )",
        ^lng, ^lat, v.longitude, v.latitude
      ),
      limit: ^limit

    # Run the query
    Repo.all(query)
  end

  @doc """
  Count the total number of venues near a city within a specified radius.
  This function doesn't use a limit, so it returns the actual total count.

  ## Options
    * `:radius_km` - search radius in kilometers (default: 50)

  ## Examples

      iex> count_venues_near_city(city, radius_km: 25)
      150

  """
  def count_venues_near_city(%City{} = city, opts \\ []) do
    {lat, lng} = City.coordinates(city)
    radius_km = Keyword.get(opts, :radius_km, 50)

    # PostGIS query using ST_DWithin for efficient distance filtering
    # We only use COUNT instead of fetching all venues
    query = from v in Venue,
      select: count(v.id),
      where: fragment(
        "ST_DWithin(
          ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
          ST_SetSRID(ST_MakePoint(CAST(? AS FLOAT), CAST(? AS FLOAT)), 4326)::geography,
          ?
        )",
        ^lng, ^lat, v.longitude, v.latitude, ^(radius_km * 1000)
      )

    # Run the query
    Repo.one(query) || 0
  end

  @doc """
  Count the total number of venues with events near a city within a specified radius.
  This function filters out venues without any associated events.

  ## Options
    * `:radius_km` - search radius in kilometers (default: 50)

  ## Examples

      iex> count_venues_with_events_near_city(city, radius_km: 25)
      120

  """
  def count_venues_with_events_near_city(%City{} = city, opts \\ []) do
    {lat, lng} = City.coordinates(city)
    radius_km = Keyword.get(opts, :radius_km, 50)

    # PostGIS query using ST_DWithin and a join with events table
    # to count only venues that have associated events
    query = from v in Venue,
      join: e in assoc(v, :events),
      select: count(v.id, :distinct),
      where: fragment(
        "ST_DWithin(
          ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
          ST_SetSRID(ST_MakePoint(CAST(? AS FLOAT), CAST(? AS FLOAT)), 4326)::geography,
          ?
        )",
        ^lng, ^lat, v.longitude, v.latitude, ^(radius_km * 1000)
      )

    # Run the query
    Repo.one(query) || 0
  end

  @doc """
  Loads all important relationships for a venue.

  ## Examples

      iex> load_venue_relations(venue)
      %Venue{...}

  """
  def load_venue_relations(venue) do
    Repo.preload(venue, [
      :city,
      events: [
        :performer,
        event_sources: [:source]
      ]
    ])
  end

  @doc """
  Find suburbs (nearby cities) within a certain radius of a given city.
  Returns cities with venue count, ordered by venue count (descending).

  ## Options
    * `:radius_km` - search radius in kilometers (default: 50)
    * `:limit` - maximum number of cities to return (default: 20)
    * `:exclude_self` - whether to exclude the origin city (default: true)

  ## Examples

      iex> find_suburbs_near_city(city, radius_km: 25)
      [%{city: %City{}, venue_count: 12, distance_km: 5.2}, ...]
  """
  def find_suburbs_near_city(%City{} = city, opts \\ []) do
    radius_km = Keyword.get(opts, :radius_km, 50)
    limit = Keyword.get(opts, :limit, 20)
    exclude_self = Keyword.get(opts, :exclude_self, true)

    {lat, lng} = City.coordinates(city)

    # Base query to find cities within radius
    query = from c in City,
            select: %{
              city: c,
              distance_km: fragment(
                "ST_Distance(
                  ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
                  ST_SetSRID(ST_MakePoint(CAST(? AS FLOAT), CAST(? AS FLOAT)), 4326)::geography
                ) / 1000.0",
                ^lng, ^lat, c.longitude, c.latitude
              )
            },
            where: fragment(
              "ST_DWithin(
                ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
                ST_SetSRID(ST_MakePoint(CAST(? AS FLOAT), CAST(? AS FLOAT)), 4326)::geography,
                ?
              )",
              ^lng, ^lat, c.longitude, c.latitude, ^(radius_km * 1000)
            )

    # Add condition to exclude the origin city if requested
    query = if exclude_self do
      from [c] in query, where: c.id != ^city.id
    else
      query
    end

    # Execute the query to get cities with distances
    cities_with_distances = Repo.all(query)

    # For each city, get the venue count within a smaller radius (10km)
    # and filter out cities with no venues
    cities_with_distances
    |> Enum.map(fn %{city: c, distance_km: distance} ->
      venue_count = count_venues_near_city(c, radius_km: 10)
      %{
        city: c,
        venue_count: venue_count,
        distance_km: distance
      }
    end)
    |> Enum.filter(fn %{venue_count: count} -> count > 0 end)
    |> Enum.sort_by(fn %{venue_count: count} -> count end, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Manually trigger a recalibration of all city coordinates.
  This schedules the DailyRecalibrateWorker to run immediately.

  Returns {:ok, %Oban.Job{}} on success or {:error, changeset} on failure.

  ## Examples

      iex> recalibrate_city_coordinates()
      {:ok, %Oban.Job{}}
  """
  def recalibrate_city_coordinates do
    %{}
    |> Oban.Job.new(
      worker: TriviaAdvisor.Locations.Oban.DailyRecalibrateWorker,
      # Pre-populate meta field with empty values
      # This creates the structure that will be shown in the UI
      meta: %{
        total_cities: 0,
        updated: 0,
        skipped: 0,
        failed: 0,
        duration_ms: 0
      }
    )
    |> Oban.insert()
  end

  @doc """
  Lists all cities for a specific country with their venue counts.

  ## Examples

      iex> list_cities_by_country_with_venue_counts(123)
      [%{id: 1, name: "London", venue_count: 120, ...}, ...]
  """
  def list_cities_by_country_with_venue_counts(country_id) do
    query = from c in City,
            where: c.country_id == ^country_id,
            left_join: v in assoc(c, :venues),
            group_by: c.id,
            select: %{
              id: c.id,
              name: c.name,
              slug: c.slug,
              latitude: c.latitude,
              longitude: c.longitude,
              venue_count: count(v.id)
            }

    Repo.all(query)
  end

  @doc """
  Get featured venues for the homepage.

  This function fetches a diverse set of venues with events, prioritizing
  venues from different cities and countries, sorted by newest first.
  If no venues with events are found, it falls back to venues without events.

  ## Options
    * `:limit` - maximum number of venues to return (default: 4)

  ## Examples

      iex> get_featured_venues(limit: 6)
      [%Venue{}, ...]
  """
  def get_featured_venues(opts \\ []) do
    limit = Keyword.get(opts, :limit, 4)

    # Start with a query for venues that have events
    venues_with_events_query = from v in Venue,
      distinct: v.id,
      join: e in assoc(v, :events),
      join: c in assoc(v, :city),
      join: country in assoc(c, :country),
      preload: [city: {c, country: country}, events: e],
      order_by: [desc: v.inserted_at]

    # Get all venues with events
    venues_with_events = Repo.all(venues_with_events_query)

    # If we have venues with events, select a diverse set
    venues = select_diverse_venues(venues_with_events, limit)

    # If we don't have enough venues with events, fall back to venues without events
    if length(venues) < limit do
      # Query for venues without the events join
      fallback_query = from v in Venue,
        distinct: v.id,
        join: c in assoc(v, :city),
        join: country in assoc(c, :country),
        preload: [city: {c, country: country}],
        order_by: [desc: v.inserted_at],
        limit: ^(limit - length(venues))

      fallback_venues = Repo.all(fallback_query)

      # Combine the venues from both queries
      venues ++ fallback_venues
    else
      venues
    end
  end

  @doc """
  Get popular cities based on venue counts with geographic clustering.

  This function finds the most popular cities by venue count, while preventing nearby
  suburbs from being counted separately. Cities within a certain distance threshold
  are clustered together, with the largest city absorbing the venue counts of nearby
  smaller cities.

  ## Options
    * `:limit` - maximum number of cities to return (default: 15)
    * `:distance_threshold` - distance in kilometers for city clustering (default: 50)
    * `:diverse_countries` - whether to select cities from different countries (default: false)

  ## Examples

      iex> get_popular_cities(limit: 10, distance_threshold: 30)
      [%{id: 1, name: "London", country_name: "United Kingdom", venue_count: 120, ...}, ...]
  """
  def get_popular_cities(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)
    distance_threshold = Keyword.get(opts, :distance_threshold, 50)
    diverse_countries = Keyword.get(opts, :diverse_countries, false)

    # Get all venues with coordinates
    venues = query_venues_with_coordinates()

    # Group venues by city for initial counting
    city_venue_counts = group_venues_by_city(venues)

    # Process cities for clustering
    processed_cities = cluster_nearby_cities(city_venue_counts, distance_threshold)

    # Get top cities diversified by country if requested
    top_cities = filter_top_cities(processed_cities, limit, diverse_countries)

    # Add image URLs to each city
    add_city_images(top_cities)
  end

  # Query venues with valid coordinates
  defp query_venues_with_coordinates do
    from(v in Venue,
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      select: %{
        id: v.id,
        city_id: v.city_id,
        lat: v.latitude,
        lng: v.longitude
      })
    |> Repo.all()
  end

  # Group venues by city and prepare initial data
  defp group_venues_by_city(venues) do
    city_data = Enum.reduce(venues, %{}, fn venue, acc ->
      # Get the city for this venue
      city = get_city!(venue.city_id)
      |> Repo.preload(:country)

      city_key = "#{city.id}:#{city.name}"
      coords = {venue.lat, venue.lng}

      city_info = Map.get(acc, city_key, %{
        id: city.id,
        name: city.name,
        slug: city.slug,
        country_name: city.country.name,
        country_id: city.country.id,
        country_code: city.country.code,
        count: 0,
        coords: coords,
        venues: []
      })

      Map.put(acc, city_key, %{
        city_info |
        count: city_info.count + 1,
        venues: [venue.id | city_info.venues]
      })
    end)

    # Sort cities by venue count
    city_data
    |> Map.to_list()
    |> Enum.sort_by(fn {_key, data} -> data.count end, :desc)
  end

  # Cluster cities based on geographic proximity
  defp cluster_nearby_cities(sorted_cities, distance_threshold) do
    Enum.reduce(sorted_cities, [], fn {city_key, city_data}, acc ->
      # Skip if this city is already absorbed by a larger city
      if already_absorbed?(acc, city_key) do
        acc
      else
        # Find cities to absorb (within distance_threshold)
        absorbed_cities = find_cities_to_absorb(sorted_cities, city_key, city_data, distance_threshold)

        # Calculate total count including absorbed cities
        total_count = city_data.count +
          Enum.sum(Enum.map(absorbed_cities, fn {_, other_data} -> other_data.count end))

        # Add to results with all the required fields for the city card component
        [%{
          id: city_data.id,
          name: city_data.name,
          slug: city_data.slug,
          country_name: city_data.country_name,
          country_id: city_data.country_id,
          country_code: city_data.country_code,
          venue_count: total_count,
          coords: city_data.coords,
          absorbed_cities: Map.new(absorbed_cities)
        } | acc]
      end
    end)
    |> Enum.sort_by(fn cluster -> cluster.venue_count end, :desc)
  end

  # Check if a city has already been absorbed by a larger city
  defp already_absorbed?(processed_cities, city_key) do
    Enum.any?(processed_cities, fn cluster ->
      Enum.any?(cluster.absorbed_cities, fn {absorbed_key, _} ->
        absorbed_key == city_key
      end)
    end)
  end

  # Find cities to absorb within the distance threshold
  defp find_cities_to_absorb(sorted_cities, city_key, city_data, distance_threshold) do
    Enum.filter(sorted_cities, fn {other_key, other_data} ->
      city_key != other_key &&
        distance_in_km(city_data.coords, other_data.coords) <= distance_threshold
    end)
  end

  # Filter top cities based on criteria
  defp filter_top_cities(processed_cities, limit, diverse_countries) do
    if diverse_countries do
      select_diverse_cities(processed_cities, limit)
    else
      Enum.take(processed_cities, limit)
    end
  end

  # Add images to city data
  defp add_city_images(cities) do
    # Get city names for batch image fetching
    city_names = Enum.map(cities, & &1.name)
    city_images = TriviaAdvisor.Services.UnsplashService.get_city_images_batch(city_names)

    # Add image URLs to each city
    Enum.map(cities, fn city ->
      # Get image data from pre-fetched batch
      image_data = Map.get(city_images, city.name, %{url: nil})

      # Extract image URL with backward compatibility
      image_url = extract_image_url(image_data)

      Map.put(city, :image_url, image_url)
    end)
  end

  # Extract image URL from various possible formats
  defp extract_image_url(image_data) do
    cond do
      is_map(image_data) && Map.has_key?(image_data, :url) -> image_data.url
      is_map(image_data) && Map.has_key?(image_data, :image_url) -> image_data.image_url
      is_binary(image_data) -> image_data
      true -> nil
    end
  end

  # Helper function to select cities from diverse countries
  defp select_diverse_cities(cities, limit) do
    # First select one city from each country
    {diverse_cities, _country_counts} =
      Enum.reduce(cities, {[], %{}}, fn city, {selected, country_counts} ->
        country_code = city.country_code
        country_count = Map.get(country_counts, country_code, 0)

        # Only take the first city from each country
        if length(selected) < limit and country_count < 1 do
          {
            [city | selected],
            Map.put(country_counts, country_code, country_count + 1)
          }
        else
          {selected, country_counts}
        end
      end)

    # Calculate how many more cities we need
    remaining = limit - length(diverse_cities)

    # If we don't have enough diverse cities, add more from top cities
    cities_to_return =
      if remaining > 0 do
        # Get cities we already selected
        selected_ids = MapSet.new(Enum.map(diverse_cities, & &1.id))

        # Add more cities not yet selected
        additional_cities = cities
        |> Enum.reject(fn city -> MapSet.member?(selected_ids, city.id) end)
        |> Enum.take(remaining)

        diverse_cities ++ additional_cities
      else
        diverse_cities
      end

    # Sort by venue count
    Enum.sort_by(cities_to_return, fn city -> city.venue_count end, :desc)
  end

  # Calculate distance between two lat/lng coordinates using Haversine formula
  defp distance_in_km({lat1, lng1}, {lat2, lng2}) do
    lat1 = if is_struct(lat1, Decimal), do: Decimal.to_float(lat1), else: lat1
    lng1 = if is_struct(lng1, Decimal), do: Decimal.to_float(lng1), else: lng1
    lat2 = if is_struct(lat2, Decimal), do: Decimal.to_float(lat2), else: lat2
    lng2 = if is_struct(lng2, Decimal), do: Decimal.to_float(lng2), else: lng2

    earth_radius = 6371 # km

    dlat = :math.pi() * (lat2 - lat1) / 180
    dlng = :math.pi() * (lng2 - lng1) / 180

    a = :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(:math.pi() * lat1 / 180) * :math.cos(:math.pi() * lat2 / 180) *
        :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    earth_radius * c
  end

  # Helper function to select venues from diverse locations
  defp select_diverse_venues(venues, limit) do
    venues
    |> Enum.reduce({[], %{}, %{}}, fn venue, {selected, city_ids, country_codes} ->
      city_id = venue.city.id
      country_code = venue.city.country.code

      # Check if we've already selected a venue from this city or country
      city_count = Map.get(city_ids, city_id, 0)
      country_count = Map.get(country_codes, country_code, 0)

      # Prioritize venues from new cities and countries
      if length(selected) < limit and (city_count == 0 or (country_count < 2 and length(selected) < limit - 2)) do
        {
          [venue | selected],
          Map.put(city_ids, city_id, city_count + 1),
          Map.put(country_codes, country_code, country_count + 1)
        }
      else
        {selected, city_ids, country_codes}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.take(limit)
    |> Repo.preload([:events, :city])
  end
end

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
    Repo.delete(country)
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
    Repo.delete(city)
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
    venue
    |> Venue.changeset(attrs)
    |> Repo.update()
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
    Repo.delete(venue)
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

  def find_or_create_city(city_title, country_code) when is_binary(city_title) and is_binary(country_code) do
    with {:ok, country} <- find_or_create_country(country_code) do
      case Repo.get_by(City, [name: city_title, country_id: country.id]) do
        nil ->
          %City{}
          |> City.changeset(%{
            name: city_title,
            country_id: country.id
          })
          |> Repo.insert()
        city -> {:ok, city}
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

      # Try to find existing venue by place_id or coordinates
      lat = Decimal.new(to_string(validated_data.lat))
      lng = Decimal.new(to_string(validated_data.lng))

      # First try by place_id
      existing_venue =
        if validated_data.place_id do
          Repo.get_by(Venue, place_id: validated_data.place_id)
        end

      # Then try by exact coordinates if no venue found
      existing_venue =
        if is_nil(existing_venue) do
          Repo.get_by(Venue, [
            latitude: lat,
            longitude: lng,
            city_id: city.id
          ])
        else
          existing_venue
        end

      case existing_venue do
        nil -> create_venue(attrs, validated_data, city)
        venue -> {:ok, venue}
      end
    end
  end

  defp validate_location_data(%{lat: lat, lng: lng, city: city, country_code: code} = data)
    when is_number(lat) and is_number(lng) and is_binary(city) and is_binary(code), do: {:ok, data}
  defp validate_location_data(_), do: {:error, "Missing required location data"}

  defp normalize_city_name(city) do
    city
    |> String.split(",")
    |> List.first()
    |> String.trim()
  end

  defp create_venue(attrs, validated_data, city) do
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
      city_id: city.id
    })
    |> Repo.insert()
  end
end

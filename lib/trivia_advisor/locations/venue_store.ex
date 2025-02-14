defmodule TriviaAdvisor.Locations.VenueStore do
  @moduledoc """
  Handles finding or creating venues, cities, and countries.
  Ensures proper relationships between venues, cities, and countries.
  """

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{Venue, City, Country}
  alias TriviaAdvisor.Scraping.GoogleLookup
  alias Ecto.Multi

  require Logger

  @doc """
  Processes venue data and stores it in the database.
  Ensures country and city exist and are properly linked.

  Returns {:ok, venue} on success or {:error, reason} on failure.
  """
  def process_venue(venue_data) do
    case validate_address(venue_data.address) do
      {:ok, address} ->
        with {:ok, location_data} <- GoogleLookup.lookup_address(address) do
          Multi.new()
          |> Multi.run(:country, fn _repo, _changes ->
            find_or_create_country(location_data["country"])
          end)
          |> Multi.run(:city, fn _repo, %{country: country} ->
            find_or_create_city(location_data["city"], country)
          end)
          |> Multi.run(:venue, fn _repo, %{city: city} ->
            find_or_create_venue(venue_data, location_data, city)
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{venue: venue}} -> {:ok, venue}
            {:error, step, reason, _changes} ->
              Logger.error("Failed to process venue at #{step}: #{Kernel.inspect(reason)}")
              {:error, reason}
          end
        end

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds or creates a country based on its code.
  Validates and normalizes country codes.
  """
  def find_or_create_country(%{"name" => name, "code" => code})
      when is_binary(name) and is_binary(code) and byte_size(name) > 0 do
    normalized_code = code |> String.trim() |> String.upcase()

    if normalized_code == "" do
      Logger.error("Invalid country code: Empty or whitespace-only")
      {:error, :invalid_country_code}
    else
      case Repo.get_by(Country, code: normalized_code) do
        nil ->
          %Country{}
          |> Country.changeset(%{name: name, code: normalized_code})
          |> Repo.insert()

        country ->
          {:ok, country}
      end
    end
  end
  def find_or_create_country(_), do: {:error, :invalid_country_data}

  @doc """
  Finds or creates a city, ensuring it's linked to the correct country.
  Validates and normalizes city names.
  """
  def find_or_create_city(nil, _country), do: {:error, :missing_city}
  def find_or_create_city(%{"name" => nil}, _country), do: {:error, :invalid_city_data}
  def find_or_create_city(%{"name" => name}, %Country{id: country_id}) do
    normalized_name = name |> String.trim() |> String.replace(~r/\s+/, " ")

    if normalized_name == "" do
      Logger.error("Invalid city name: Empty or whitespace-only")
      {:error, :invalid_city_name}
    else
      case Repo.get_by(City, name: normalized_name, country_id: country_id) do
        nil ->
          %City{}
          |> City.changeset(%{name: normalized_name, country_id: country_id})
          |> Repo.insert()

        city ->
          {:ok, city}
      end
    end
  end
  def find_or_create_city(_, _), do: {:error, :invalid_city_data}

  @doc """
  Finds or creates a venue, storing its location details.
  Updates existing venues if needed while preserving place_id.
  """
  def find_or_create_venue(venue_data, location_data, %City{id: city_id}) do
    with {:ok, lat, lng} <- extract_coordinates(location_data),
         {:ok, venue_attrs} <- build_venue_attrs(venue_data, location_data, lat, lng, city_id) do
      find_and_upsert_venue(venue_attrs, location_data["place_id"])
    end
  end

  # Private functions

  defp validate_address(nil) do
    Logger.error("Missing address in venue data")
    {:error, :missing_address}
  end
  defp validate_address(address) when is_binary(address) do
    case String.trim(address) do
      "" ->
        Logger.error("Invalid address: Empty or whitespace-only")
        {:error, :invalid_address}
      valid_address -> {:ok, valid_address}
    end
  end

  defp extract_coordinates(location_data) do
    lat = get_in(location_data, ["location", "lat"])
    lng = get_in(location_data, ["location", "lng"])

    if is_nil(lat) or is_nil(lng) do
      Logger.error("""
      Missing geocoordinates in location data:
      #{Kernel.inspect(location_data)}
      """)
      {:error, :missing_geocoordinates}
    else
      {:ok, lat, lng}
    end
  end

  defp build_venue_attrs(venue_data, location_data, lat, lng, city_id) do
    {:ok, %{
      name: venue_data.name,
      address: venue_data.address,
      latitude: lat,
      longitude: lng,
      place_id: location_data["place_id"],
      city_id: city_id,
      phone: venue_data.phone,
      website: venue_data.website
    }}
  end

  defp find_and_upsert_venue(venue_attrs, place_id) do
    venue_query =
      if place_id do
        [place_id: place_id]
      else
        [name: venue_attrs.name, city_id: venue_attrs.city_id]
      end

    case Repo.get_by(Venue, venue_query) do
      nil -> create_venue(venue_attrs)
      venue -> update_venue(venue, venue_attrs)
    end
  end

  defp create_venue(attrs) do
    Logger.info("""
    Creating new venue: #{attrs.name}
    City ID: #{attrs.city_id}
    Address: #{attrs.address}
    Coordinates: #{attrs.latitude},#{attrs.longitude}
    """)

    %Venue{}
    |> Venue.changeset(attrs)
    |> Repo.insert()
  end

  defp update_venue(venue, attrs) do
    updated_attrs = if venue.place_id, do: Map.drop(attrs, [:place_id]), else: attrs

    if Map.equal?(updated_attrs, venue |> Map.take(Map.keys(updated_attrs))) do
      Logger.debug("No changes needed for venue: #{venue.name}")
      {:ok, venue}
    else
      Logger.info("""
      Updating venue #{venue.id} (#{venue.name})
      Changes: #{Kernel.inspect(Map.drop(updated_attrs, [:place_id]))}
      """)
      venue
      |> Venue.changeset(updated_attrs)
      |> Repo.update()
    end
  end
end

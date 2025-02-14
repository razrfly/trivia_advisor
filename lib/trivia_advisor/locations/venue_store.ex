defmodule TriviaAdvisor.Locations.VenueStore do
  @moduledoc """
  Handles finding or creating venues, cities, and countries.
  Ensures proper relationships between venues, cities, and countries.
  """

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{Venue, City, Country}
  alias TriviaAdvisor.Scraping.GoogleLookup

  require Logger

  @doc """
  Processes venue data and stores it in the database.
  Ensures country and city exist and are properly linked.

  Returns {:ok, venue} on success or {:error, reason} on failure.
  """
  def process_venue(venue_data) do
    case venue_data.address do
      nil ->
        Logger.error("Missing address in venue data: #{inspect(venue_data)}")
        {:error, :missing_address}
      address ->
        with {:ok, location_data} <- GoogleLookup.lookup_address(address),
             {:ok, country} <- find_or_create_country(location_data["country"]),
             {:ok, city} <- find_or_create_city(location_data["city"], country),
             {:ok, venue} <- find_or_create_venue(venue_data, location_data, city) do
          {:ok, venue}
        else
          {:error, :missing_country} ->
            Logger.error("No country data found for venue: #{inspect(venue_data)}")
            {:error, :missing_country}
          {:error, :missing_city} ->
            Logger.error("No city data found for venue: #{inspect(venue_data)}")
            {:error, :missing_city}
          {:error, reason} ->
            Logger.error("Failed to process venue: #{inspect(venue_data)}, reason: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Finds or creates a country based on its code.
  Expects country data with "name" and "code" keys.
  """
  def find_or_create_country(nil), do: {:error, :missing_country}
  def find_or_create_country(%{"name" => nil, "code" => _code}), do: {:error, :invalid_country_data}
  def find_or_create_country(%{"name" => name, "code" => code}) when is_binary(code) do
    normalized_code = String.upcase(code)

    case Repo.get_by(Country, code: normalized_code) do
      nil ->
        %Country{}
        |> Country.changeset(%{name: name, code: normalized_code})
        |> Repo.insert()

      country ->
        {:ok, country}
    end
  end
  def find_or_create_country(_), do: {:error, :invalid_country_data}

  @doc """
  Finds or creates a city, ensuring it's linked to the correct country.
  Expects city data with "name" key and a country struct.
  """
  def find_or_create_city(nil, _country), do: {:error, :missing_city}
  def find_or_create_city(%{"name" => nil}, _country), do: {:error, :invalid_city_data}
  def find_or_create_city(%{"name" => name}, %Country{id: country_id}) do
    normalized_name = name |> String.trim() |> String.replace(~r/\s+/, " ")

    case Repo.get_by(City, name: normalized_name, country_id: country_id) do
      nil ->
        %City{}
        |> City.changeset(%{name: normalized_name, country_id: country_id})
        |> Repo.insert()

      city ->
        {:ok, city}
    end
  end
  def find_or_create_city(_, _), do: {:error, :invalid_city_data}

  @doc """
  Finds or creates a venue, storing its location details.
  Updates existing venues if needed while preserving place_id.
  Logs creation of new venues and any changes to existing ones.
  Returns {:error, :missing_geocoordinates} if lat/lng are missing.
  """
  def find_or_create_venue(venue_data, location_data, %City{id: city_id}) do
    lat = get_in(location_data, ["location", "lat"])
    lng = get_in(location_data, ["location", "lng"])

    if is_nil(lat) or is_nil(lng) do
      Logger.error("""
      Skipping venue #{venue_data.name} - Missing geocoordinates
      Address: #{venue_data.address}
      Location data: #{inspect(location_data)}
      """)
      {:error, :missing_geocoordinates}
    else
      venue_attrs = %{
        name: venue_data.name,
        address: venue_data.address,
        latitude: lat,
        longitude: lng,
        place_id: location_data["place_id"],
        city_id: city_id,
        phone: venue_data.phone,
        website: venue_data.website
      }

      venue_query =
        case location_data["place_id"] do
          nil -> [name: venue_data.name, city_id: city_id]
          place_id -> [place_id: place_id]
        end

      case Repo.get_by(Venue, venue_query) do
        nil ->
          Logger.info("""
          Creating new venue: #{venue_data.name}
          City ID: #{city_id}
          Address: #{venue_data.address}
          Coordinates: #{lat},#{lng}
          """)
          %Venue{}
          |> Venue.changeset(venue_attrs)
          |> Repo.insert()

        %Venue{place_id: existing_place_id} = venue ->
          venue_attrs =
            if existing_place_id do
              Logger.debug("Preserving existing place_id: #{existing_place_id}")
              Map.delete(venue_attrs, :place_id)
            else
              venue_attrs
            end

          changeset = Venue.changeset(venue, venue_attrs)

          case changeset.changes do
            changes when changes == %{} ->
              Logger.debug("No changes needed for venue: #{venue.name}")
              {:ok, venue}

            changes ->
              Logger.info("""
              Updating venue #{venue.id} (#{venue.name})
              Changes: #{inspect(changes)}
              """)
              Repo.update(changeset)
          end
      end
    end
  end
end

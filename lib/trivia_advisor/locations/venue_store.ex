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
    case validate_address(venue_data) do
      {:ok, address} ->
        with {:ok, location_data} <- GoogleLookup.lookup_address(address) do
          Multi.new()
          |> Multi.run(:country, fn _repo, _changes ->
            case find_or_create_country(location_data["country"]) do
              {:ok, country} -> {:ok, country}
              {:error, reason} ->
                {:error, {:country, reason, location_data["country"]}}
            end
          end)
          |> Multi.run(:city, fn _repo, %{country: country} ->
            case find_or_create_city(location_data["city"], country) do
              {:ok, city} -> {:ok, city}
              {:error, %Ecto.Changeset{errors: [slug: {_, [constraint: :unique]}]}} = error ->
                # If it's a unique constraint error, try to find the existing city
                city_name = get_in(location_data, ["city", "name"])
                normalized_name = city_name |> String.trim() |> String.replace(~r/\s+/, " ")
                slug = normalized_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

                case Repo.get_by(City, slug: slug, country_id: country.id) do
                  nil -> error
                  city -> {:ok, city}
                end
              {:error, reason} ->
                {:error, {:city, reason, location_data["city"]}}
            end
          end)
          |> Multi.run(:venue, fn _repo, %{city: city} ->
            case find_or_create_venue(venue_data, location_data, city) do
              {:ok, venue} -> {:ok, venue}
              {:error, reason} ->
                {:error, {:venue, reason, venue_data}}
            end
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{venue: venue}} -> {:ok, venue}
            {:error, _step, {component, reason, data}, _changes} ->
              Logger.error("""
              Failed to process #{component}
              Reason: #{inspect(reason)}
              Data: #{inspect(data)}
              Venue: #{venue_data.title}
              """)
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
      Logger.error("❌ Invalid country code: Empty or whitespace-only")
      {:error, :invalid_country_code}
    else
      case Repo.get_by(Country, code: normalized_code) do
        nil ->
          Logger.info("🏳️ Creating new country: #{name} (#{normalized_code})")
          %Country{}
          |> Country.changeset(%{name: name, code: normalized_code})
          |> Repo.insert()

        country ->
          Logger.info("✅ Found existing country: #{name}")
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
  def find_or_create_city(%{"name" => name}, %Country{id: country_id, name: country_name}) do
    normalized_name = name |> String.trim() |> String.replace(~r/\s+/, " ")
    slug = normalized_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

    if normalized_name == "" do
      Logger.error("❌ Invalid city name: Empty or whitespace-only")
      {:error, :invalid_city_name}
    else
      # First try to find by slug only since it's globally unique
      case Repo.get_by(City, slug: slug) do
        nil ->
          Logger.info("🏙️ Creating new city: #{normalized_name} in #{country_name}")
          %City{}
          |> City.changeset(%{
            name: normalized_name,
            country_id: country_id,
            slug: slug
          })
          |> Repo.insert()
          |> case do
            {:ok, city} -> {:ok, city}
            {:error, %Ecto.Changeset{errors: [slug: {_, [constraint: :unique]}]}} ->
              # Double-check by slug in case of race condition
              case Repo.get_by(City, slug: slug) do
                nil ->
                  Logger.error("""
                  ❌ Failed to retrieve existing city after unique constraint error
                  Name: #{normalized_name}
                  Slug: #{slug}
                  """)
                  {:error, :city_not_found}
                city ->
                  Logger.info("🔄 Found existing city by slug: #{city.name}")
                  {:ok, city}
              end
            {:error, changeset} ->
              Logger.error("""
              ❌ Failed to create city
              Name: #{normalized_name}
              Error: #{inspect(changeset.errors)}
              """)
              {:error, changeset}
          end

        city ->
          Logger.info("✅ Found existing city: #{normalized_name}")
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
         venue_attrs = %{
           name: venue_data.title,
           address: venue_data.address,
           latitude: lat,
           longitude: lng,
           place_id: location_data["place_id"],
           city_id: city_id,
           phone: venue_data.phone,
           website: venue_data.website
         } do
      find_and_upsert_venue(venue_attrs, location_data["place_id"])
    end
  end

  # Private functions

  defp validate_address(%{title: name, address: nil}) do
    Logger.error("""
    ❌ Missing address in venue data
    Venue: #{name}
    """)
    {:error, :missing_address}
  end
  defp validate_address(%{title: name, address: address}) when is_binary(address) do
    case String.trim(address) do
      "" ->
        Logger.error("""
        ❌ Invalid address: Empty or whitespace-only
        Venue: #{name}
        Raw address: #{inspect(address)}
        """)
        {:error, :invalid_address}
      valid_address ->
        Logger.info("🌍 Looking up address: #{valid_address}")
        {:ok, valid_address}
    end
  end

  defp validate_address(venue_data) do
    Logger.error("""
    ❌ Invalid venue data structure
    Expected keys: title, address
    Got: #{inspect(venue_data)}
    """)
    {:error, :invalid_venue_data}
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

  defp find_and_upsert_venue(venue_attrs, place_id) do
    # First try to find by place_id if available
    venue = if place_id do
      Repo.get_by(Venue, place_id: place_id)
    end

    # If not found by place_id, try by name and city
    venue = venue || Repo.get_by(Venue, name: venue_attrs.name, city_id: venue_attrs.city_id)

    case venue do
      nil ->
        Logger.info("""
        🏠 Creating new venue: #{venue_attrs.name}
        Address: #{venue_attrs.address}
        Coordinates: #{venue_attrs.latitude},#{venue_attrs.longitude}
        """)
        %Venue{}
        |> Venue.changeset(venue_attrs)
        |> Repo.insert()
        |> case do
          {:ok, venue} -> {:ok, venue}
          {:error, %Ecto.Changeset{errors: [slug: {_, [constraint: :unique]}]} = changeset} ->
            Logger.info("🔄 Venue exists with slug, retrieving: #{venue_attrs.name}")
            # If insert failed due to unique constraint, get existing record
            case Repo.get_by(Venue, slug: get_in(changeset.changes, [:slug])) do
              nil -> {:error, changeset}
              venue -> update_venue(venue, venue_attrs)
            end
          {:error, changeset} -> {:error, changeset}
        end

      venue ->
        Logger.info("✅ Found existing venue: #{venue.name}")
        update_venue(venue, venue_attrs)
    end
  end

  defp update_venue(venue, attrs) do
    updated_attrs = if venue.place_id, do: Map.drop(attrs, [:place_id]), else: attrs
    current_attrs = venue |> Map.from_struct() |> Map.drop([:__meta__, :inserted_at, :updated_at])

    if Map.equal?(Map.drop(current_attrs, [:updated_at]), Map.drop(updated_attrs, [:updated_at])) do
      Logger.debug("No changes needed for venue: #{venue.name}")
      {:ok, venue}
    else
      diff = Map.drop(updated_attrs, [:place_id])
      Logger.info("""
      Updating venue #{venue.id} (#{venue.name})
      Changes: #{inspect(diff)}
      """)
      venue
      |> Venue.changeset(updated_attrs)
      |> Repo.update()
    end
  end
end

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
  def process_venue(%{address: address} = attrs) when is_binary(address) do
    # Check for existing venue with coordinates
    case find_existing_venue(attrs) do
      %{latitude: lat, longitude: lng} = existing when not is_nil(lat) and not is_nil(lng) ->
        # Skip API call entirely if we have coordinates
        Logger.info("✅ Using stored coordinates for venue: #{attrs.name}")
        {:ok, existing}

      _ ->
        # No existing venue with coordinates, proceed with API lookup
        lookup_opts = [venue_name: attrs.name]
        process_new_venue(attrs, lookup_opts)
    end
  end

  defp find_existing_venue(%{name: name} = attrs) do
    # First try to find by place_id if available
    venue = if attrs[:place_id] do
      Repo.get_by(Venue, place_id: attrs.place_id)
    end

    # Then try by name and city_id if available
    venue = venue || if attrs[:city_id] do
      Repo.get_by(Venue, name: name, city_id: attrs.city_id)
    end

    # Finally try by name and address
    venue = venue || Repo.get_by(Venue, name: name, address: attrs[:address])

    case venue do
      %Venue{latitude: lat, longitude: lng} = v when not is_nil(lat) and not is_nil(lng) ->
        Repo.preload(v, [city: :country])
      _ -> nil
    end
  end
  defp find_existing_venue(_), do: nil

  defp process_new_venue(attrs, lookup_opts) do
    case GoogleLookup.lookup_address(attrs.address, lookup_opts) do
      {:ok, location_data} ->
        # Check if venue exists by place_id from Google lookup
        existing = if location_data["place_id"] do
          Repo.get_by(Venue, place_id: location_data["place_id"])
        end

        case existing do
          %Venue{latitude: lat, longitude: lng} = venue when not is_nil(lat) and not is_nil(lng) ->
            Logger.info("✅ Found existing venue by place_id: #{venue.name}")
            {:ok, venue}

          _ ->
            # Get or create the city and country
            with {:ok, country} <- find_or_create_country(location_data["country"]),
                 {:ok, city} <- find_or_create_city(location_data["city"], country) do
              # Structure venue data to match expected format
              venue_data = %{
                title: attrs.name,
                address: attrs.address,
                phone: attrs[:phone] || location_data["phone"],
                website: attrs[:website] || location_data["website"],
                facebook: attrs[:facebook],
                instagram: attrs[:instagram]
              }

              find_or_create_venue(venue_data, location_data, city)
            end
        end
      error -> error
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
  def find_or_create_city(%{"name" => name}, %Country{id: country_id, name: country_name, code: country_code}) do
    normalized_name = name |> String.trim() |> String.replace(~r/\s+/, " ")
    base_slug = normalized_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
    country_specific_slug = "#{base_slug}-#{String.downcase(country_code)}"

    if normalized_name == "" do
      Logger.error("❌ Invalid city name: Empty or whitespace-only")
      {:error, :invalid_city_name}
    else
      # First try to find by case-insensitive name and country_id
      import Ecto.Query
      case Repo.one(
        from c in City,
        where: fragment("LOWER(?)", c.name) == ^String.downcase(normalized_name)
          and c.country_id == ^country_id,
        limit: 1
      ) do
        %City{} = city ->
          Logger.info("✅ Found existing city: #{city.name} in #{country_name}")
          {:ok, city}

        nil ->
          # Create new city with country-specific slug
          Logger.info("🏙️ Creating new city: #{normalized_name} in #{country_name} (#{country_specific_slug})")

          attrs = %{
            name: normalized_name,
            country_id: country_id,
            slug: country_specific_slug
          }

          %City{}
          |> City.changeset(attrs)
          |> Repo.insert()
          |> case do
            {:ok, city} ->
              Logger.info("✅ Created new city: #{city.name} in #{country_name} (#{city.slug})")
              {:ok, city}
            {:error, %{errors: [{:name, {_, [constraint: :unique]} = _error} | _]} = _changeset} ->
              # If we hit the unique constraint, try one final time to find the city
              case Repo.one(
                from c in City,
                where: fragment("LOWER(?)", c.name) == ^String.downcase(normalized_name)
                  and c.country_id == ^country_id,
                limit: 1
              ) do
                %City{} = city ->
                  Logger.info("✅ Found existing city after constraint error: #{city.name} in #{country_name}")
                  {:ok, city}
                nil ->
                  Logger.error("❌ City exists but couldn't be found: #{normalized_name} in #{country_name}")
                  {:error, :city_exists_but_not_found}
              end
            {:error, changeset} ->
              Logger.error("""
              ❌ Failed to create city
              Name: #{normalized_name}
              Country: #{country_name}
              Error: #{inspect(changeset.errors)}
              """)
              {:error, changeset}
          end
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
           website: venue_data.website,
           facebook: venue_data.facebook,
           instagram: venue_data.instagram,
           postcode: location_data["postal_code"]["code"],
           metadata: extract_metadata(location_data)
         },
         {:ok, venue} <- find_and_upsert_venue(venue_attrs, location_data["place_id"]) do
      {:ok, venue}
    end
  end

  # Private functions

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

  defp extract_metadata(location_data) do
    %{
      "formatted_address" => location_data["formatted_address"],
      "google_maps_url" => location_data["google_maps_url"],
      "place_id" => location_data["place_id"],
      "opening_hours" => location_data["opening_hours"],
      "phone" => location_data["phone"],
      "rating" => location_data["rating"],
      "types" => location_data["types"],
      "website" => location_data["website"],
      "city" => location_data["city"],
      "state" => location_data["state"],
      "country" => location_data["country"],
      "postal_code" => location_data["postal_code"]
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
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
          {:ok, venue} -> {:ok, Repo.preload(venue, [city: :country])}
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

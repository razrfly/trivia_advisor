defmodule TriviaAdvisor.Scraping.Oban.GoogleLookupJob do
  @moduledoc """
  Oban job for handling all Google API interactions (Places & Geocoding).

  This job is responsible for:
  1. Fetching venue details from Google Places API only when necessary
  2. Falling back to Google Maps Geocoding API when Places API fails
  3. Processing venue images immediately after fetching venue details
  4. Returning a fully populated venue to VenueStore

  All Google API calls MUST go through this job to ensure proper rate limiting
  and tracking of API usage.
  """

  use Oban.Worker,
    queue: :google_api,
    max_attempts: 3,
    priority: 1

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{Venue, City, Country}
  alias TriviaAdvisor.Scraping.GoogleLookup
  alias TriviaAdvisor.Services.{GooglePlacesService, GooglePlaceImageStore}

  @doc """
  Finds city and country for given coordinates using geocoding API.
  Returns {:ok, %{city_id: city_id}} or {:error, reason}.

  This function is intended to be used directly from VenueStore when we already have
  coordinates but need to determine the city and country for a venue.

  This uses the much cheaper Geocoding API instead of Places API, providing just
  the information needed for creating a venue with valid city_id.
  """
  def find_city_from_coordinates(lat, lng, venue_name \\ nil) do
    Logger.info("🌍 Finding city data for coordinates: #{lat}, #{lng}")

    # Convert string coordinates to float if needed
    {lat, lng} = case {lat, lng} do
      {lat, lng} when is_binary(lat) and is_binary(lng) ->
        {lat_float, _} = Float.parse(lat)
        {lng_float, _} = Float.parse(lng)
        {lat_float, lng_float}
      {lat, lng} when is_number(lat) and is_number(lng) ->
        {lat, lng}
      _ ->
        Logger.error("❌ Invalid coordinates format: lat=#{inspect(lat)}, lng=#{inspect(lng)}")
        {:error, :invalid_coordinates}
    end

    # Short-circuit on invalid coordinates
    if is_tuple(lat) and elem(lat, 0) == :error, do: lat, else: find_city_from_valid_coordinates(lat, lng, venue_name)
  end

  # Implementation with validated float coordinates
  defp find_city_from_valid_coordinates(lat, lng, venue_name) when is_number(lat) and is_number(lng) do
    venue_name = venue_name || "Venue at #{lat}, #{lng}"

    # Use the lookup_by_coordinates from GoogleLookup but with minimum fields
    # This is much more economical than a full Places lookup
    venue_opts = [venue_name: venue_name, fields: ["addressComponents"]]

    case GoogleLookup.lookup_by_coordinates(lat, lng, venue_opts) do
      {:ok, location_data} ->
        Logger.info("✅ Found location data for coordinates")

        # First create the country
        with {:ok, country} <- find_or_create_country(location_data["country"]),
             {:ok, city} <- find_or_create_city(location_data["city"], country) do

          Logger.info("✅ Successfully found city #{city.name} (#{city.id}) for coordinates")
          {:ok, %{city_id: city.id}}
        else
          {:error, :missing_city} ->
            Logger.error("❌ No city found in geocoding data")
            {:error, :missing_city}

          {:error, reason} = error ->
            Logger.error("❌ Failed to process city/country: #{inspect(reason)}")
            error
        end

      {:error, reason} = error ->
        Logger.error("❌ Failed to geocode coordinates: #{inspect(reason)}")
        error
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    venue_name = args["venue_name"]
    address = args["address"]
    existing_venue_id = args["existing_venue_id"]

    Logger.metadata(google_job: true, venue_name: venue_name)
    Logger.info("🔍 Processing Google lookup for venue: #{venue_name}")

    # Additional fields from args
    additional_attrs = extract_additional_attrs(args)

    # Check if we need to lookup the venue by ID first
    venue = if existing_venue_id, do: Repo.get(Venue, existing_venue_id), else: nil

    case venue do
      # If venue exists and has coordinates, just return it (skip API call)
      %Venue{latitude: lat, longitude: lng} = venue when not is_nil(lat) and not is_nil(lng) ->
        Logger.info("⏭️ Skipping Google API lookup - venue already has coordinates")
        maybe_fetch_images(venue)

      # Either venue doesn't exist or doesn't have coordinates, proceed with API lookup
      _ ->
        lookup_opts = [venue_name: venue_name]

        # Check if we have coordinates in the args
        lat = args["lat"] || args["latitude"]
        lng = args["lng"] || args["longitude"]

        # Use direct coordinate lookup if coordinates are provided
        lookup_result = if lat && lng do
          Logger.info("🌎 Using coordinates directly: #{lat}, #{lng}")
          # Use the new function that directly searches by coordinates
          GoogleLookup.lookup_by_coordinates(lat, lng, [venue_name: venue_name, address: address])
        else
          # Fall back to address lookup
          Logger.info("🏠 Using address lookup: #{address}")
          GoogleLookup.lookup_address(address, lookup_opts)
        end

        # Process the lookup result
        case lookup_result do
          {:ok, location_data} ->
            Logger.info("✅ Google API lookup successful for venue: #{venue_name}")
            Logger.info("📊 API source: #{location_data["source"] || "geocoding"}")

            # Process the venue with the location data
            process_venue_with_location(venue_name, address, location_data, additional_attrs)

          {:error, reason} ->
            Logger.error("❌ Google API lookup failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Process the venue using the location data from Google
  defp process_venue_with_location(venue_name, address, location_data, additional_attrs) do
    # Extract coordinates
    with {:ok, lat, lng} <- extract_coordinates(location_data) do
      # Find or create country and city
      result = with {:ok, country} <- find_or_create_country(location_data["country"]),
                    {:ok, city} <- find_or_create_city(location_data["city"], country) do

        # Create venue attributes
        venue_attrs = %{
          name: venue_name,
          address: address,
          latitude: lat,
          longitude: lng,
          place_id: location_data["place_id"],
          city_id: city.id,
          phone: additional_attrs[:phone] || location_data["phone"],
          website: additional_attrs[:website] || location_data["website"],
          facebook: additional_attrs[:facebook],
          instagram: additional_attrs[:instagram],
          postcode: location_data["postal_code"]["code"],
          metadata: extract_metadata(location_data)
        }

        # Find existing venue or create a new one
        case find_and_upsert_venue(venue_attrs, location_data["place_id"]) do
          {:ok, venue} ->
            # Fetch and attach images directly within this job
            updated_venue = fetch_and_attach_images(venue)
            {:ok, updated_venue}

          {:error, changeset} ->
            Logger.error("❌ Failed to create/update venue: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      end

      case result do
        {:ok, venue} -> {:ok, venue}
        error -> error
      end
    else
      {:error, reason} ->
        Logger.error("❌ Missing geo coordinates: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Extract additional attributes from args
  defp extract_additional_attrs(args) do
    %{
      phone: args["phone"],
      website: args["website"],
      facebook: args["facebook"],
      instagram: args["instagram"]
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  # Extract coordinates from location data
  defp extract_coordinates(location_data) do
    # Try both formats - old API format (lat/lng) and new API format (latitude/longitude)
    lat = get_in(location_data, ["location", "lat"]) ||
          get_in(location_data, ["location", "latitude"])
    lng = get_in(location_data, ["location", "lng"]) ||
          get_in(location_data, ["location", "longitude"])

    if is_nil(lat) or is_nil(lng) do
      Logger.error("Missing geocoordinates in location data: #{inspect(location_data)}")
      {:error, :missing_geocoordinates}
    else
      {:ok, lat, lng}
    end
  end

  # Extract metadata from location data
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
      "postal_code" => location_data["postal_code"],
      "api_source" => location_data["source"] || "geocoding"
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  # Find existing country or create a new one
  defp find_or_create_country(%{"name" => name, "code" => code})
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
  defp find_or_create_country(_), do: {:error, :invalid_country_data}

  # Find existing city or create a new one
  defp find_or_create_city(nil, _country), do: {:error, :missing_city}
  defp find_or_create_city(%{"name" => nil}, _country), do: {:error, :invalid_city_data}
  defp find_or_create_city(%{"name" => name}, %Country{id: country_id, name: country_name, code: country_code}) do
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
  defp find_or_create_city(_, _), do: {:error, :invalid_city_data}

  # Find and upsert venue
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

  # Update venue with new attributes
  defp update_venue(venue, attrs) do
    updated_attrs = if venue.place_id, do: Map.drop(attrs, [:place_id]), else: attrs

    venue
    |> Venue.changeset(updated_attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_venue} ->
        {:ok, Repo.preload(updated_venue, [city: :country])}
      error -> error
    end
  end

  # Fetch and attach images to venue
  defp fetch_and_attach_images(venue) do
    if has_place_id?(venue) do
      Logger.info("🖼️ Fetching Google Place images for venue: #{venue.name}")

      case GooglePlacesService.get_venue_images(venue.id) do
        [] ->
          Logger.info("ℹ️ No Google Place images found for venue: #{venue.name}")
          venue

        images when is_list(images) ->
          Logger.info("🖼️ Processing #{length(images)} images for venue: #{venue.name}")
          case process_images(venue, images) do
            {:ok, updated_venue} ->
              Logger.info("✅ Successfully attached images to venue: #{venue.name}")
              updated_venue
            {:error, reason} ->
              Logger.error("❌ Failed to process images: #{inspect(reason)}")
              venue
          end

        _ ->
          Logger.error("❌ Invalid images data received")
          venue
      end
    else
      Logger.info("⏭️ Skipping image fetch - venue has no place_id")
      venue
    end
  end

  # Check if venue has a place_id
  defp has_place_id?(venue) do
    place_id = Map.get(venue, :place_id)
    is_binary(place_id) && byte_size(place_id) > 0
  end

  # Process images
  defp process_images(venue, _image_urls) do
    # Log what we're doing
    Logger.info("🔄 Processing images for venue: #{venue.name} (place_id: #{venue.place_id})")

    # Use the existing GooglePlaceImageStore functionality
    result = GooglePlaceImageStore.process_venue_images(venue)

    # Log the result for debugging
    case result do
      {:ok, updated_venue} ->
        Logger.info("""
        ✅ Successfully processed images for venue: #{venue.name}
        Image count: #{length(updated_venue.google_place_images)}
        Image data: #{inspect(updated_venue.google_place_images)}
        """)
        {:ok, updated_venue}
      {:error, reason} ->
        Logger.error("❌ Failed to process images: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # For existing venues with coordinates, check if we need images
  defp maybe_fetch_images(venue) do
    updated_venue = fetch_and_attach_images(venue)
    {:ok, updated_venue}
  end
end

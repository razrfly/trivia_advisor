defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Handles Google Places and Geocoding API lookups for venue addresses.
  Uses the new Places API v2 (https://places.googleapis.com/v1)
  """

  require Logger
  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)

  # Business fields from Places API v2
  @place_fields [
    "displayName",
    "formattedAddress",
    "location",
    "internationalPhoneNumber",
    "nationalPhoneNumber",
    "websiteUri",
    "regularOpeningHours",
    "businessStatus",
    "rating",
    "userRatingCount",
    "types",
    "addressComponents",
    "priceLevel",
    "shortFormattedAddress",
    "googleMapsUri"
  ]

  @doc """
  Looks up venue details using both Google Places and Geocoding APIs.
  Returns {:ok, venue_details} or {:error, reason}.

  If existing_coordinates is provided, skips the API call and returns cached data.
  """
  def lookup_address(address, opts \\ [])
  def lookup_address("", _opts) do
    Logger.error("❌ Critical error: Missing required address")
    {:error, :missing_address}
  end
  def lookup_address(nil, _opts), do: lookup_address("", [])

  def lookup_address(address, opts) do
    # Extract existing coordinates if provided
    case Keyword.get(opts, :existing_coordinates) do
      {lat, lng} when is_number(lat) and is_number(lng) ->
        venue_name = Keyword.get(opts, :venue_name, "Unknown Venue")
        Logger.info("⏭️ Using existing coordinates for venue: #{venue_name}")
        {:ok, build_cached_response(venue_name, address, lat, lng)}

      _ ->
        lookup_from_api(address, opts)
    end
  end

  @doc """
  Looks up venue details using coordinates directly.
  This is useful when you already have coordinates and want to find the Google Place details.
  Returns {:ok, venue_details} or {:error, reason}.

  This avoids geocoding and city lookup issues when coordinates are already known.
  """
  def lookup_by_coordinates(lat, lng, opts \\ [])

  def lookup_by_coordinates(lat, lng, opts) when is_binary(lat) and is_binary(lng) do
    {lat_float, _} = Float.parse(lat)
    {lng_float, _} = Float.parse(lng)
    lookup_by_coordinates(lat_float, lng_float, opts)
  end

  def lookup_by_coordinates(lat, lng, opts) when is_number(lat) and is_number(lng) do
    Logger.info("🔍 Looking up place by coordinates: #{lat}, #{lng}")

    with {:ok, api_key} <- get_api_key(),
         venue_name = Keyword.get(opts, :venue_name, "Venue at #{lat}, #{lng}"),
         _ = Logger.info("📡 Querying Google Places API with coordinates for venue: #{inspect(venue_name)}"),
         {:ok, search_results} <- find_places_by_coordinates(lat, lng, api_key, opts) do

      case search_results do
        %{"places" => [place | _]} ->
          place_id = place["id"]
          display_name = place["displayName"]["text"] || place["displayName"] || "Unknown Place"
          Logger.info("✅ Found place #{inspect(display_name)}, getting details...")

          case get_place_details(place_id, api_key) do
            {:ok, place_details} ->
              # Add latitude and longitude to details if not present
              details_with_coords = ensure_coordinates(place_details, lat, lng)

              # Extract address components if present
              details_with_components = if place_details["addressComponents"] do
                # Process address components into the expected format
                address_components = extract_address_components_v2(place_details["addressComponents"])
                Map.merge(details_with_coords, address_components)
              else
                details_with_coords
              end

              # Add source marker
              final_details = Map.put(details_with_components, "source", "places")

              {:ok, final_details}

            error ->
              Logger.error("❌ Failed to get place details: #{inspect(error)}")
              error
          end

        %{"places" => []} ->
          Logger.info("⚠️ No places found at these coordinates, returning basic data")

          # Return a basic response with the coordinates we know
          venue_name = Keyword.get(opts, :venue_name, "Unknown Venue")
          address = Keyword.get(opts, :address, "Unknown Address")
          {:ok, build_cached_response(venue_name, address, lat, lng)}

        _ ->
          Logger.error("❌ Invalid response format from Places API")
          {:error, :invalid_response_format}
      end
    else
      {:error, reason} ->
        Logger.error("❌ Failed to look up place by coordinates: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp lookup_from_api(address, opts) do
    with {:ok, api_key} <- get_api_key(),
         venue_name = Keyword.get(opts, :venue_name, ""),
         search_text = (if venue_name == "", do: address, else: "#{venue_name}, #{address}"),
         _ = Logger.info("📡 Querying Google Maps API with: \"#{search_text}\""),
         {:ok, search_results} <- find_places_from_text(search_text, api_key, opts),
         {:ok, maybe_place_id} <- extract_place_id(search_results) do

      result = case maybe_place_id do
        nil ->
          # No place_id found, use Geocoding API with just the address
          Logger.info("No place_id found for #{address}, using Geocoding API")
          lookup_by_geocoding(address, api_key, opts)

        place_id ->
          # Get business details and geocoding data
          with {:ok, place_details} <- get_place_details(place_id, api_key),
               location = get_in(place_details, ["location"]),
               {:ok, geocoding_data} <- lookup_geocode_by_latlng(location, api_key, opts) do
            merged_data = merge_api_responses(place_details, geocoding_data)
            _ = Logger.info("✅ Found business details for #{venue_name}")
            {:ok, normalize_business_data(merged_data)}
          else
            {:error, reason} ->
              Logger.warning("Failed to get place details: #{inspect(reason)}, falling back to Geocoding API")
              lookup_by_geocoding(address, api_key, opts)
            error ->
              Logger.warning("Unexpected error in place details: #{inspect(error)}, falling back to Geocoding API")
              lookup_by_geocoding(address, api_key, opts)
          end
      end

      result
    end
  end

  defp lookup_by_geocoding(address, api_key, _opts) do
    Logger.info("Using Geocoding API for address: #{address}")
    params = %{
      address: address,
      key: api_key
    }

    url = "https://maps.googleapis.com/maps/api/geocode/json?" <> URI.encode_query(params)
    case make_api_request(url) do
      {:ok, response} ->
        case handle_geocoding_response(response) do
          {:ok, geocoding_data} ->
            merged_data = add_geocoding_source(geocoding_data)
            {:ok, normalize_business_data(merged_data)}
          error -> error
        end
      error -> error
    end
  end

  defp add_geocoding_source(data) do
    # Extract address components first, then add the source
    components = extract_address_components(data["address_components"] || [])

    data
    |> Map.merge(%{
      "city" => components["city"],
      "state" => components["state"],
      "country" => components["country"],
      "postal_code" => components["postal_code"]
    })
    |> Map.put("source", "geocoding")
  end

  defp lookup_geocode_by_latlng(%{"latitude" => lat, "longitude" => lng}, api_key, _opts) do
    params = %{
      latlng: "#{lat},#{lng}",
      key: api_key
    }

    url = "https://maps.googleapis.com/maps/api/geocode/json?" <> URI.encode_query(params)
    case make_api_request(url) do
      {:ok, response} -> handle_geocoding_response(response)
      error -> error
    end
  end
  defp lookup_geocode_by_latlng(_, _, _), do: {:error, :invalid_location}

  defp handle_geocoding_response(%{"status" => "OK", "results" => [result | _]}) do
    # Remove any place_id from geocoding result to prevent confusion with business IDs
    result = Map.delete(result, "place_id")
    {:ok, result}
  end
  defp handle_geocoding_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Geocoding API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp normalize_business_data(details) do
    # Convert from new Places API format to our standard format
    %{
      # Basic details (available for both businesses and addresses)
      "name" => details["displayName"] || details["name"],
      "formatted_address" => details["formattedAddress"] || details["formatted_address"],
      "place_id" => details["id"] || details["place_id"],
      "location" => extract_location(details),

      # Business-only details (nil for non-business addresses)
      "phone" => details["internationalPhoneNumber"] || details["nationalPhoneNumber"] || details["formatted_phone_number"],
      "website" => details["websiteUri"] || details["website"],
      "google_maps_url" => details["googleMapsUri"] || details["url"],
      "types" => details["types"],
      "opening_hours" => extract_hours(details["regularOpeningHours"] || details["opening_hours"]),
      "rating" => extract_rating_data(details),

      # Address components (from Geocoding API)
      "city" => details["city"],
      "state" => details["state"],
      "country" => details["country"],
      "postal_code" => details["postal_code"],

      # Keep track of API source
      "source" => details["source"] || "places"
    }
  end

  defp extract_rating_data(details) do
    cond do
      details["rating"] && is_number(details["rating"]) ->
        %{
          "value" => details["rating"],
          "total_ratings" => details["userRatingCount"] || details["user_ratings_total"] || 0
        }
      details["rating"] && is_map(details["rating"]) ->
        %{
          "value" => details["rating"]["value"],
          "total_ratings" => details["rating"]["userRatingCount"] || 0
        }
      true -> nil
    end
  end

  defp merge_api_responses(place_details, geocoding_data) do
    components = extract_address_components(geocoding_data["address_components"] || [])

    # Only keep place_id from Places API results
    place_id = if place_details["source"] == "places", do: (place_details["id"] || place_details["place_id"])

    # Start with place details and add geocoding components
    place_details
    |> Map.merge(%{
      "city" => components["city"],
      "state" => components["state"],
      "country" => components["country"],
      "postal_code" => components["postal_code"]
    })
    |> Map.put("place_id", place_id)  # Explicitly set place_id based on source
  end

  defp extract_location(details) do
    cond do
      details["location"] && Map.has_key?(details["location"], "latitude") ->
        %{
          "lat" => details["location"]["latitude"],
          "lng" => details["location"]["longitude"]
        }
      details["geometry"] && details["geometry"]["location"] ->
        %{
          "lat" => details["geometry"]["location"]["lat"],
          "lng" => details["geometry"]["location"]["lng"]
        }
      true -> nil
    end
  end

  defp extract_hours(%{"periods" => periods, "weekdayDescriptions" => weekday_text}) do
    %{
      "periods" => periods,
      "formatted" => weekday_text
    }
  end
  defp extract_hours(%{"periods" => periods, "weekday_text" => weekday_text}) do
    %{
      "periods" => periods,
      "formatted" => weekday_text
    }
  end
  defp extract_hours(_), do: nil

  defp extract_place_id(%{"id" => place_id}) when is_binary(place_id), do: {:ok, place_id}
  defp extract_place_id(%{"places" => [%{"id" => place_id} | _]}) when is_binary(place_id), do: {:ok, place_id}
  defp extract_place_id(%{"place_id" => place_id}) when is_binary(place_id), do: {:ok, place_id}
  defp extract_place_id(%{"candidates" => [%{"place_id" => place_id} | _]}) when is_binary(place_id), do: {:ok, place_id}
  defp extract_place_id(_), do: {:ok, nil}  # Return nil instead of error to trigger fallback

  defp get_api_key do
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ ->
        Logger.error("❌ Critical error: Missing Google Maps API key")
        {:error, :missing_api_key}
    end
  end

  defp find_places_from_text(input, api_key, _opts) do
    # Using the new Places API v2 search endpoint
    url = "https://places.googleapis.com/v1/places:searchText"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", "places.id,places.displayName,places.formattedAddress,places.types,places.location"}
    ]

    body = Jason.encode!(%{
      "textQuery" => input,
      "maxResultCount" => 1
    })

    case @http_client.post(url, body, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, response} -> handle_places_search_response(response)
          {:error, error} ->
            Logger.error("Failed to decode API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status, body: body}} ->
        error_message = extract_error_message(body)
        Logger.error("❌ Google Places API error: HTTP #{status} - #{error_message}")
        {:error, error_message}

      {:error, error} ->
        Logger.error("API request failed: #{inspect(error)}")
        {:error, "Request failed"}
    end
  end

  defp extract_error_message(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} -> message
      {:ok, %{"error_message" => message}} -> message
      _ -> "Unknown error"
    end
  end

  defp get_place_details(place_id, api_key) do
    # Using the new Places API v2 details endpoint
    url = "https://places.googleapis.com/v1/places/#{place_id}"

    fields_mask = Enum.join(@place_fields, ",")

    headers = [
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", fields_mask}
    ]

    case @http_client.get(url, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, place_details} ->
            # Mark as Places API data and ensure the ID is set
            place_details = place_details
              |> Map.put("id", place_id)
              |> Map.put("source", "places")

            {:ok, place_details}

          {:error, error} ->
            Logger.error("Failed to decode API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status, body: body}} ->
        error_message = extract_error_message(body)
        Logger.error("Google Place Details API error: HTTP #{status} - #{error_message}")
        {:error, error_message}

      {:error, error} ->
        Logger.error("API request failed: #{inspect(error)}")
        {:error, "Request failed"}
    end
  end

  defp handle_places_search_response(%{"places" => places}) when is_list(places) and length(places) > 0 do
    Logger.info("Places API search found #{length(places)} results")
    {:ok, %{"places" => places}}
  end

  defp handle_places_search_response(%{"places" => []}) do
    Logger.info("No results found in Places API, falling back to geocoding")
    {:ok, nil}
  end

  defp handle_places_search_response(response) when is_map(response) and map_size(response) == 0 do
    Logger.info("Empty response from Places API, falling back to geocoding")
    {:ok, nil}
  end

  # Catch-all for any other response format
  defp handle_places_search_response(response) do
    Logger.error("❌ Unexpected Places API response format: #{inspect(response)}")
    {:ok, nil}  # Fall back to geocoding instead of failing
  end

  defp make_api_request(url) do
    case @http_client.get(url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} -> {:ok, response}
          {:error, error} ->
            Logger.error("Failed to decode API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("Google API HTTP #{status}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("API request failed: #{inspect(error)}")
        {:error, "Request failed"}
    end
  end

  defp extract_address_components(components) when is_list(components) do
    %{
      "country" => extract_component(components, "country"),
      "city" => extract_component(components, "locality") ||
                extract_component(components, "postal_town") ||
                extract_component(components, "sublocality"),
      "state" => extract_component(components, "administrative_area_level_1"),
      "postal_code" => extract_component(components, "postal_code")
    }
  end
  defp extract_address_components(_), do: %{
    "country" => nil,
    "city" => nil,
    "state" => nil,
    "postal_code" => nil
  }

  defp extract_component(components, type) do
    case Enum.find(components, &(type in &1["types"])) do
      nil -> nil
      component -> %{
        "name" => component["long_name"],
        "code" => component["short_name"]
      }
    end
  end

  defp build_cached_response(name, address, lat, lng) do
    %{
      "name" => name,
      "formatted_address" => address,
      "place_id" => nil,
      "location" => %{
        "lat" => lat,
        "lng" => lng
      },
      "phone" => nil,
      "website" => nil,
      "google_maps_url" => nil,
      "types" => [],
      "opening_hours" => nil,
      "rating" => nil,
      "city" => nil,
      "state" => nil,
      "country" => nil,
      "postal_code" => nil,
      "cached" => true
    }
  end

  @doc """
  Find places near specific coordinates using Google Places API's searchNearby endpoint.
  Returns {:ok, search_results} or {:error, reason}.
  """
  def find_places_by_coordinates(lat, lng, api_key, opts \\ []) do
    # Default radius in meters
    radius = Keyword.get(opts, :radius, 50)

    # Using the Places API v2 nearbySearch endpoint
    url = "https://places.googleapis.com/v1/places:searchNearby"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", "places.id,places.displayName,places.formattedAddress,places.types,places.location"}
    ]

    body = Jason.encode!(%{
      "locationRestriction" => %{
        "circle" => %{
          "center" => %{
            "latitude" => lat,
            "longitude" => lng
          },
          "radius" => radius
        }
      },
      "rankPreference" => "DISTANCE",
      "maxResultCount" => 3  # Get a few results to increase chances of finding a match
    })

    case @http_client.post(url, body, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, response} -> handle_places_search_response(response)
          {:error, error} ->
            Logger.error("Failed to decode API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status, body: body}} ->
        error_message = extract_error_message(body)
        Logger.error("❌ Google Places API error: HTTP #{status} - #{error_message}")
        {:error, error_message}

      {:error, error} ->
        Logger.error("API request failed: #{inspect(error)}")
        {:error, "Request failed"}
    end
  end

  # Make sure coordinates are in the response
  defp ensure_coordinates(place_details, lat, lng) do
    if get_in(place_details, ["location", "latitude"]) do
      place_details
    else
      Map.put(place_details, "location", %{
        "latitude" => lat,
        "longitude" => lng
      })
    end
  end

  # Extract address components from Places API v2 response
  defp extract_address_components_v2(components) when is_list(components) do
    # Find components by type
    country = find_component_by_type(components, ["country"])
    city = find_component_by_type(components, ["locality", "administrative_area_level_2", "postal_town"])
    state = find_component_by_type(components, ["administrative_area_level_1"])
    postal_code = find_component_by_type(components, ["postal_code"])

    # Build component data with proper format for VenueStore
    %{
      "country" => extract_component_data(country),
      "city" => extract_component_data(city),
      "state" => extract_component_data(state),
      "postal_code" => extract_component_data(postal_code)
    }
  end

  defp extract_address_components_v2(_), do: %{
    "country" => nil,
    "city" => nil,
    "state" => nil,
    "postal_code" => nil
  }

  # Extract data from a component
  defp extract_component_data(nil), do: nil
  defp extract_component_data(component) do
    %{
      "name" => component["longText"],
      "code" => component["shortText"]
    }
  end

  # Find component by type
  defp find_component_by_type(components, types) do
    Enum.find(components, fn component ->
      Enum.any?(component["types"], fn type -> type in types end)
    end)
  end
end

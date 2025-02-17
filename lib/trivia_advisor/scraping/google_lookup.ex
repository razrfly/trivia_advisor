defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Handles Google Places and Geocoding API lookups for venue addresses.
  """

  require Logger
  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)

  # Business fields from Places API
  @place_fields [
    "name",
    "formatted_address",
    "geometry",
    "formatted_phone_number",
    "international_phone_number",
    "website",
    "url",
    "opening_hours",
    "types",
    "rating",
    "user_ratings_total"
  ]

  @doc """
  Looks up venue details using both Google Places and Geocoding APIs.
  Returns {:ok, venue_details} or {:error, reason}.
  """
  def lookup_address(address, opts \\ []) do
    with {:ok, api_key} <- get_api_key(),
         # Step 1: Try to get place_id from Places API
         {:ok, place_data} <- find_place_from_text(address, api_key, opts),
         {:ok, maybe_place_id} <- extract_place_id(place_data) do

      case maybe_place_id do
        nil ->
          # No place_id found, use Geocoding API directly
          Logger.info("No place_id found for #{address}, using Geocoding API")
          lookup_by_geocoding(address, api_key, opts)

        place_id ->
          # Get business details and geocoding data
          with {:ok, place_details} <- get_place_details(place_id, api_key),
               location = get_in(place_details, ["geometry", "location"]),
               {:ok, geocoding_data} <- lookup_geocode_by_latlng(location, api_key, opts) do
            merged_data = merge_api_responses(place_details, geocoding_data)
            {:ok, normalize_business_data(merged_data)}
          else
            error ->
              Logger.warning("Failed to get place details: #{inspect(error)}, falling back to Geocoding API")
              lookup_by_geocoding(address, api_key, opts)
          end
      end
    end
  end

  defp lookup_by_geocoding(address, api_key, opts) do
    case lookup_geocode_by_address(address, api_key, opts) do
      {:ok, geocoding_data} ->
        Logger.info("📍 Using Geocoding API for #{address} - no business details available")

        # Extract only the fields we need, explicitly excluding place_id
        basic_data = %{
          "name" => extract_street_address(geocoding_data["formatted_address"]),
          "formatted_address" => geocoding_data["formatted_address"],
          "place_id" => nil,  # Always nil for non-business addresses
          "geometry" => %{"location" => get_in(geocoding_data, ["geometry", "location"])},
          "phone" => nil,
          "website" => nil,
          "google_maps_url" => nil,
          "types" => ["street_address"],
          "opening_hours" => nil,
          "rating" => nil,
          "source" => "geocoding"
        }

        # Extract address components, ensuring no place_id is included
        components = extract_address_components(geocoding_data["address_components"] || [])
        final_data = Map.merge(basic_data, %{
          "city" => components["city"],
          "state" => components["state"],
          "country" => components["country"],
          "postal_code" => components["postal_code"]
        })

        {:ok, normalize_business_data(final_data)}
      error -> error
    end
  end

  # Extract just the street address part for non-business addresses
  defp extract_street_address(formatted_address) do
    formatted_address
    |> String.split(",")
    |> List.first()
    |> String.trim()
  end

  defp lookup_geocode_by_address(address, api_key, _opts) do
    params = %{
      address: address,
      key: api_key
    }

    url = "https://maps.googleapis.com/maps/api/geocode/json?" <> URI.encode_query(params)
    case make_api_request(url) do
      {:ok, response} -> handle_geocoding_response(response)
      error -> error
    end
  end

  defp lookup_geocode_by_latlng(%{"lat" => lat, "lng" => lng}, api_key, _opts) do
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
    %{
      # Basic details (available for both businesses and addresses)
      "name" => details["name"],
      "formatted_address" => details["formatted_address"],
      "place_id" => details["place_id"],
      "location" => extract_location(details["geometry"]),

      # Business-only details (nil for non-business addresses)
      "phone" => details["international_phone_number"] || details["formatted_phone_number"],
      "website" => details["website"],
      "google_maps_url" => details["url"],
      "types" => details["types"],
      "opening_hours" => extract_hours(details["opening_hours"]),
      "rating" => rating_data(details),

      # Address components (from Geocoding API)
      "city" => details["city"],
      "state" => details["state"],
      "country" => details["country"],
      "postal_code" => details["postal_code"]
    }
  end

  defp rating_data(details) do
    if details["rating"] do
      %{
        "value" => details["rating"],
        "total_ratings" => details["user_ratings_total"]
      }
    else
      nil
    end
  end

  defp merge_api_responses(place_details, geocoding_data) do
    components = extract_address_components(geocoding_data["address_components"] || [])

    # Only keep place_id from Places API results
    place_id = if place_details["source"] == "places", do: place_details["place_id"]

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

  defp extract_location(%{"location" => location}) when is_map(location) do
    %{
      "lat" => location["lat"],
      "lng" => location["lng"]
    }
  end
  defp extract_location(_), do: nil

  defp extract_hours(%{"periods" => periods, "weekday_text" => weekday_text}) do
    %{
      "periods" => periods,
      "formatted" => weekday_text
    }
  end
  defp extract_hours(_), do: nil

  defp extract_place_id(%{"place_id" => place_id}) when is_binary(place_id), do: {:ok, place_id}
  defp extract_place_id(_), do: {:ok, nil}  # Return nil instead of error to trigger fallback

  defp get_api_key do
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp find_place_from_text(input, api_key, _opts) do
    params = %{
      input: input,
      inputtype: "textquery",
      fields: "place_id,types",
      key: api_key
    }

    case make_api_request(places_url(params)) do
      {:ok, response} -> handle_places_response(response)
      error -> error
    end
  end

  defp get_place_details(place_id, api_key) do
    params = %{
      place_id: place_id,
      fields: Enum.join(["place_id" | @place_fields], ","),
      key: api_key
    }

    url = "https://maps.googleapis.com/maps/api/place/details/json?" <> URI.encode_query(params)
    case make_api_request(url) do
      {:ok, response} ->
        # Ensure we're using the Places API place_id and mark the source
        response =
          response
          |> put_in(["result", "place_id"], place_id)  # Keep original Places API place_id
          |> put_in(["result", "source"], "places")    # Mark as Places API data
          |> update_in(["result", "types"], &(if &1, do: &1, else: []))  # Ensure types is a list
        handle_place_details_response(response)
      error -> error
    end
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => []}) do
    Logger.warning("No results found in Places API response")
    {:ok, nil}
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => [candidate | _]}) do
    Logger.debug("Places API candidate: #{inspect(candidate)}")

    # Check if this is a business or just a street address
    if is_business?(candidate["types"]) do
      {:ok, candidate}
    else
      Logger.info("Found location but not a business, using geocoding instead")
      {:ok, nil}
    end
  end

  defp handle_places_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Places API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp handle_place_details_response(%{"status" => "OK", "result" => result}) do
    {:ok, result}
  end

  defp handle_place_details_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Place Details API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp places_url(params) do
    "https://maps.googleapis.com/maps/api/place/findplacefromtext/json?" <> URI.encode_query(params)
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
      %{"long_name" => name, "short_name" => code} -> %{"name" => name, "code" => code}
      _ -> nil
    end
  end

  # Helper to determine if a type indicates a business
  defp is_business?(nil), do: false
  defp is_business?(types) do
    business_types = [
      "establishment",
      "point_of_interest",
      "food",
      "restaurant",
      "bar",
      "cafe",
      "night_club",
      "lodging",
      "store",
      "shopping_mall",
      "movie_theater",
      "museum",
      "art_gallery",
      "gym",
      "spa",
      "casino"
    ]

    # Must have "establishment" or "point_of_interest" AND not be just a street_address
    has_business_type = Enum.any?(types, &(&1 in business_types))
    not_street_address = "street_address" not in types

    has_business_type and not_street_address
  end
end

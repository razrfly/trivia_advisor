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
         # Step 1: Get business details from Places API
         {:ok, place_data} <- find_place_from_text(address, api_key, opts),
         {:ok, place_id} <- extract_place_id(place_data),
         {:ok, place_details} <- get_place_details(place_id, api_key),
         # Step 2: Get address components from Geocoding API using lat/lng
         location = get_in(place_details, ["geometry", "location"]),
         {:ok, geocoding_data} <- lookup_geocode_by_latlng(location, api_key, opts) do

      # Merge data from both APIs
      merged_data = merge_api_responses(place_details, geocoding_data)
      {:ok, normalize_business_data(merged_data)}
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
    {:ok, result}
  end
  defp handle_geocoding_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Geocoding API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp normalize_business_data(details) do
    %{
      # Business details from Places API
      "name" => details["name"],
      "formatted_address" => details["formatted_address"],
      "place_id" => details["place_id"],
      "location" => extract_location(details["geometry"]),
      "phone" => details["international_phone_number"] || details["formatted_phone_number"],
      "website" => details["website"],
      "google_maps_url" => details["url"],
      "types" => details["types"],
      "opening_hours" => extract_hours(details["opening_hours"]),
      "rating" => %{
        "value" => details["rating"],
        "total_ratings" => details["user_ratings_total"]
      },
      # Address components from Geocoding API
      "city" => details["city"],
      "state" => details["state"],
      "country" => details["country"],
      "postal_code" => details["postal_code"]
    }
  end

  defp merge_api_responses(place_details, geocoding_data) do
    # Extract address components from geocoding data
    components = extract_address_components(geocoding_data["address_components"] || [])

    # Start with Places API data
    place_details
    # Add Geocoding API address components
    |> Map.merge(%{
      "city" => components["city"],
      "state" => components["state"],
      "country" => components["country"],
      "postal_code" => components["postal_code"]
    })
    # Ensure place_id is preserved
    |> Map.put_new("place_id", place_details["place_id"])
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
  defp extract_place_id(_), do: {:error, :no_place_id}

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
      fields: "place_id",
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
        # Add place_id to the result since it might not be in the response
        response = put_in(response, ["result", "place_id"], place_id)
        handle_place_details_response(response)
      error -> error
    end
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => []}) do
    Logger.warning("No results found in Places API response")
    {:ok, %{}}
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => [candidate | _]}) do
    {:ok, candidate}
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
end

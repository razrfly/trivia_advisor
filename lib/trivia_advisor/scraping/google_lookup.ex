defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Handles Google Places and Geocoding API lookups for venue addresses.
  """

  require Logger

  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)

  @doc """
  Looks up an address using Google Places API first, falling back to Geocoding API.
  Returns {:ok, data} or {:error, reason}.
  """
  def lookup_address(address, opts \\ []) do
    with {:ok, api_key} <- get_api_key(),
         {:ok, place_data} <- find_place_from_text(address, api_key, opts) do

      case normalize_place_data(place_data) do
        %{"country" => nil} = data ->
          Logger.info("Missing country, attempting Geocoding API for #{address}")
          case lookup_geocode(address, api_key, opts) do
            {:ok, geo_data} ->
              # Merge geocoding data, preferring existing non-nil values
              {:ok, Map.merge(geo_data, data, fn _k, v1, v2 -> v2 || v1 end)}
            {:error, :no_results} -> {:error, :no_results}
            {:error, _} -> {:ok, data}  # Keep original data if geocoding fails
          end

        data -> {:ok, data}
      end
    end
  end

  defp find_place_from_text(input, api_key, _opts) do
    params = %{
      input: input,
      inputtype: "textquery",
      fields: "formatted_address,name,place_id,geometry,address_components",
      key: api_key
    }

    case @http_client.get(places_url(params), [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} -> handle_places_response(response)
          {:error, error} ->
            Logger.error("Failed to decode Places API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("Google Places API HTTP #{status}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("Google Places API request failed: #{inspect(error)}")
        {:error, "Request failed"}
    end
  end

  defp lookup_geocode(address, api_key, _opts) do
    params = %{
      address: address,
      key: api_key
    }

    case @http_client.get(geocoding_url(params), [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} -> handle_geocoding_response(response)
          {:error, error} ->
            Logger.error("Failed to decode Geocoding API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("Google Geocoding API HTTP #{status}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("Google Geocoding API request failed: #{inspect(error)}")
        {:error, "Request failed"}
    end
  end

  defp get_api_key do
    case Application.get_env(:trivia_advisor, :google_api_key) do
      nil ->
        Logger.error("Google Maps API key is missing!")
        {:error, "API key missing"}
      "" ->
        Logger.error("Google Maps API key is empty!")
        {:error, "API key missing"}
      key -> {:ok, key}
    end
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => candidates}) do
    {:ok, List.first(candidates)}
  end

  defp handle_places_response(%{"status" => "ZERO_RESULTS"}) do
    {:error, :no_results}
  end

  defp handle_places_response(%{"status" => "OVER_QUERY_LIMIT"}) do
    {:error, :over_query_limit}
  end

  defp handle_places_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Places API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp handle_geocoding_response(%{"status" => "OK", "results" => []}) do
    {:error, :no_results}
  end

  defp handle_geocoding_response(%{"status" => "OK", "results" => [result | _]}) do
    {:ok, normalize_geocoding_data(result)}
  end

  defp handle_geocoding_response(%{"status" => "OVER_QUERY_LIMIT"}) do
    {:error, :over_query_limit}
  end

  defp handle_geocoding_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Geocoding API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp normalize_place_data(place) when is_map(place) do
    components = extract_address_components(place["address_components"])

    %{
      "name" => place["name"],
      "formatted_address" => place["formatted_address"],
      "place_id" => Map.get(place, "place_id", nil),
      "location" => extract_location(place["geometry"]),
      "country" => components["country"],
      "city" => components["city"],
      "state" => components["state"],
      "postal_code" => components["postal_code"]
    }
  end
  defp normalize_place_data(_), do: %{
    "name" => nil,
    "formatted_address" => nil,
    "place_id" => nil,
    "location" => nil,
    "country" => nil,
    "city" => nil,
    "state" => nil,
    "postal_code" => nil
  }

  defp normalize_geocoding_data(result) do
    components = extract_address_components(result["address_components"] || [])

    %{
      "name" => result["formatted_address"],  # Use formatted_address as name for geocoding results
      "formatted_address" => result["formatted_address"],
      "place_id" => Map.get(result, "place_id", nil),
      "location" => extract_location(result["geometry"]),
      "country" => components["country"],
      "city" => components["city"],
      "state" => components["state"],
      "postal_code" => components["postal_code"]
    }
  end

  defp extract_address_components(components) when is_list(components) do
    result = Enum.reduce(components, %{}, fn component, acc ->
      types = component["types"] || []

      cond do
        # Check for country type
        "country" in types ->
          Map.put(acc, "country", %{
            "name" => component["long_name"],
            "code" => component["short_name"]
          })

        # Check for locality type
        "locality" in types ->
          Map.put(acc, "city", %{
            "name" => component["long_name"],
            "code" => component["short_name"]
          })

        # Check for state/province type
        "administrative_area_level_1" in types ->
          Map.put(acc, "state", %{
            "name" => component["long_name"],
            "code" => component["short_name"]
          })

        # Check for postal code type
        "postal_code" in types ->
          Map.put(acc, "postal_code", %{
            "name" => component["long_name"],
            "code" => component["short_name"]
          })

        true -> acc
      end
    end)

    Map.merge(%{
      "country" => nil,
      "city" => nil,
      "state" => nil,
      "postal_code" => nil
    }, result)
  end
  defp extract_address_components(_), do: %{
    "country" => nil,
    "city" => nil,
    "state" => nil,
    "postal_code" => nil
  }

  defp extract_location(%{"location" => location}) do
    %{
      "lat" => location["lat"],
      "lng" => location["lng"]
    }
  end
  defp extract_location(_), do: nil

  defp places_url(params) do
    "https://maps.googleapis.com/maps/api/place/findplacefromtext/json?" <> URI.encode_query(params)
  end

  defp geocoding_url(params) do
    "https://maps.googleapis.com/maps/api/geocode/json?" <> URI.encode_query(params)
  end
end

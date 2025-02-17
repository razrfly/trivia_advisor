defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Handles Google Places API lookups for venue addresses.
  """

  require Logger
  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)

  # Business fields we want to fetch from the Places API
  @place_fields [
    "name",
    "formatted_address",
    "geometry",
    "address_components",
    "formatted_phone_number",
    "international_phone_number",
    "website",
    "url",           # Google Maps URL
    "opening_hours", # Hours of operation
    "types",         # Business categories
    "rating",
    "user_ratings_total"
  ]

  @doc """
  Looks up venue details using Google Places API.
  Returns {:ok, venue_details} or {:error, reason}.
  """
  def lookup_address(address, opts \\ []) do
    with {:ok, api_key} <- get_api_key(),
         {:ok, place_data} <- find_place_from_text(address, api_key, opts),
         {:ok, place_id} <- extract_place_id(place_data),
         {:ok, details} <- get_place_details(place_id, api_key) do
      Logger.debug("Place details response: #{inspect(details)}")
      {:ok, normalize_business_data(details)}
    end
  end

  defp normalize_business_data(details) do
    %{
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
      }
    }
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
      fields: Enum.join(@place_fields, ","),
      key: api_key
    }

    url = "https://maps.googleapis.com/maps/api/place/details/json?" <> URI.encode_query(params)
    case make_api_request(url) do
      {:ok, response} -> handle_place_details_response(response)
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
end

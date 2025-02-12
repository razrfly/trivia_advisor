defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Module for looking up place data from Google Places and Geocoding APIs.
  """

  @base_url "https://maps.googleapis.com"
  @places_path "/maps/api/place"
  @geocoding_path "/maps/api/geocode/json"

  @doc """
  Looks up an address using Google Places API, falling back to Geocoding API if needed.
  Returns location data enriched with country and city information.
  """
  def lookup_address(address, opts \\ []) when is_binary(address) do
    base_url = Keyword.get(opts, :base_url, @base_url)
    case find_place_from_text(address, base_url) do
      {:ok, %{"candidates" => [place | _]}} ->
        case lookup_place_id(place["place_id"], opts) do
          {:ok, %{"result" => details}} -> {:ok, enrich_place_data(details)}
          error -> error
        end
      {:ok, %{"candidates" => []}} ->
        case lookup_geocode(address, [base_url: base_url]) do
          {:ok, %{"results" => [result | _]}} -> {:ok, enrich_place_data(result)}
          other -> other
        end
      error -> error
    end
  end

  @doc """
  Fetches detailed place data from Google Places API using a place_id.
  """
  def lookup_place_id(place_id, opts \\ []) when is_binary(place_id) do
    base_url = Keyword.get(opts, :base_url, @base_url)
    params = %{
      place_id: place_id,
      key: api_key(),
      fields: "formatted_address,geometry,name,place_id,types,address_components"
    }

    "#{base_url}#{@places_path}/details/json"
    |> HTTPoison.get([], params: params)
    |> handle_response()
  end

  @doc """
  Looks up address components and coordinates using Google Geocoding API.
  """
  def lookup_geocode(address, opts \\ []) when is_binary(address) do
    base_url = Keyword.get(opts, :base_url, @base_url)
    params = %{
      address: address,
      key: api_key(),
      result_type: "locality"  # Filter for city-level results
    }

    "#{base_url}#{@geocoding_path}"
    |> HTTPoison.get([], params: params)
    |> handle_response()
  end

  # Private Functions

  defp find_place_from_text(input, base_url) when is_binary(base_url) do
    params = %{
      input: input,
      inputtype: "textquery",
      key: api_key(),
      fields: "formatted_address,geometry,name,place_id"
    }

    "#{base_url}#{@places_path}/findplacefromtext/json"
    |> HTTPoison.get([], params: params)
    |> handle_response()
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, %{"status" => "OK"} = response} -> {:ok, response}
      {:ok, %{"status" => error, "error_message" => message}} -> {:error, "#{error}: #{message}"}
      {:ok, %{"status" => error}} -> {:error, error}
      error -> {:error, "Failed to decode response: #{inspect(error)}"}
    end
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}) do
    {:error, "HTTP Status #{status}: #{body}"}
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, "HTTP Error: #{inspect(reason)}"}
  end

  defp api_key do
    key = Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI)[:google_maps_api_key]
    if is_nil(key) or key == "", do: raise("Google Maps API key not configured!")
    key
  end

  defp enrich_place_data(place) do
    place
    |> extract_location_components()
    |> Map.merge(place)
  end

  defp extract_location_components(%{"address_components" => components}) do
    %{
      "country" => extract_component(components, "country") || %{"name" => "", "code" => ""},
      "city" => extract_component(components, "locality") || %{"name" => "", "code" => ""},
      "state" => extract_component(components, "administrative_area_level_1") || %{"name" => "", "code" => ""},
      "postal_code" => extract_component(components, "postal_code") || %{"name" => "", "code" => ""}
    }
  end

  defp extract_location_components(_), do: %{
    "country" => %{"name" => "", "code" => ""},
    "city" => %{"name" => "", "code" => ""},
    "state" => %{"name" => "", "code" => ""},
    "postal_code" => %{"name" => "", "code" => ""}
  }

  defp extract_component(components, type) do
    case Enum.find(components, &(type in &1["types"])) do
      %{"long_name" => name, "short_name" => code} ->
        %{
          "name" => name,
          "code" => code
        }
      _ -> nil
    end
  end
end

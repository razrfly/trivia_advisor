defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Handles Google Places and Geocoding API lookups for venue addresses.
  Includes rate limiting and fallback strategies.
  """

  use Agent
  require Logger

  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)
  @retry_wait_ms 5_000  # Wait 5 seconds between retries
  @max_retries 3

  def start_link(_) do
    case Agent.start_link(fn -> nil end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Looks up an address using Google Places API first, falling back to Geocoding API.
  Returns {:ok, data} or {:error, reason}.
  """
  def lookup_address(address, opts \\ []) do
    with {:ok, api_key} <- get_api_key(),
         {:ok, place_data} <- find_place_from_text(address, api_key, opts) do

      place_info = normalize_place_data(place_data)

      if has_required_fields?(place_info) and not Map.equal?(place_info, %{}) do
        {:ok, place_info}
      else
        Logger.warning("""
        ⚠️ Missing location data for #{address}:
        #{inspect_missing_fields(place_info)}
        Attempting Geocoding API lookup...
        """)

        case lookup_geocode(address, api_key, opts) do
          {:ok, geo_data} when is_map(geo_data) ->
            geo_info = normalize_location_data(geo_data)

            # Merge data, preferring geocoding results for location fields
            merged_data = Map.merge(place_info, geo_info, fn
              _k, v1, v2 when is_nil(v2) -> v1
              _k, _v1, v2 -> v2
            end)

            if has_required_fields?(merged_data) do
              {:ok, merged_data}
            else
              Logger.error("""
              ❌ Failed to extract location data:
              Address: #{address}
              Places API: #{inspect_missing_fields(place_info)}
              Geocoding API: #{inspect_missing_fields(geo_info)}
              """)
              {:error, :no_results}
            end

          {:error, reason} ->
            Logger.error("""
            ❌ Geocoding API failed for #{address}:
            Reason: #{inspect(reason)}
            Places API data: #{inspect_missing_fields(place_info)}
            """)
            {:error, reason}
        end
      end
    end
  end

  defp find_place_from_text(input, api_key, _opts) do
    params = %{
      input: input,
      inputtype: "textquery",
      fields: "formatted_address,name,place_id,geometry",
      key: api_key
    }

    Logger.debug("🔍 Places API Request: #{mask_api_key(places_url(params))}")
    case make_api_request("Places", places_url(params)) do
      {:ok, response} -> handle_places_response(response)
      error -> error
    end
  end

  defp lookup_geocode(address, api_key, _opts) do
    params = %{
      address: address,
      key: api_key
    }

    case make_api_request("Geocoding", geocoding_url(params)) do
      {:ok, response} -> handle_geocoding_response(response)
      error -> error
    end
  end

  defp get_api_key do
    unless Process.whereis(__MODULE__) do
      start_link(nil)
    end

    case Agent.get(__MODULE__, & &1) do
      nil ->
        key =
          System.get_env("GOOGLE_MAPS_API_KEY")
          |> fallback_to_config()

        if is_binary(key) and byte_size(key) > 0 do
          Agent.update(__MODULE__, fn _ -> key end)
          {:ok, key}
        else
          Logger.error("""
          ❌ Google Maps API key is missing or empty!
          Check:
          1. Environment variable GOOGLE_MAPS_API_KEY
          2. Application config :trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI
          """)
          {:error, :missing_api_key}
        end

      key -> {:ok, key}
    end
  end

  defp fallback_to_config(nil) do
    case Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI, %{}) do
      env when is_list(env) -> Keyword.get(env, :google_maps_api_key)
      env when is_map(env) -> Map.get(env, :google_maps_api_key)
      _ -> nil
    end
  end
  defp fallback_to_config(key), do: key

  defp handle_places_response(%{"status" => "OK", "candidates" => []}) do
    Logger.debug("No results found in Places API response")
    {:ok, %{}}
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => candidates}) do
    {:ok, List.first(candidates)}
  end

  defp handle_places_response(%{"status" => "OVER_QUERY_LIMIT"}) do
    retry_google_api("Places API rate limit exceeded")
  end

  defp handle_places_response(%{"status" => "INVALID_REQUEST", "error_message" => msg}) do
    Logger.error("Google Places API error: INVALID_REQUEST - #{msg}")
    {:error, "Invalid request to Places API: #{msg}"}
  end

  defp handle_places_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Places API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp handle_geocoding_response(%{"status" => "OK", "results" => []}) do
    Logger.debug("Empty results from Geocoding API")
    {:ok, %{}}
  end

  defp handle_geocoding_response(%{"status" => "OK", "results" => [result | _]}) do
    {:ok, result}
  end

  defp handle_geocoding_response(%{"status" => "OVER_QUERY_LIMIT"}) do
    retry_google_api("Geocoding API rate limit exceeded")
  end

  defp handle_geocoding_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Geocoding API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp normalize_place_data(place), do: normalize_location_data(place)

  defp normalize_location_data(nil), do: nil
  defp normalize_location_data(data) when is_map(data) do
    components = extract_address_components(data["address_components"] || [])
    city = components["city"] ||
           components["sublocality"] ||
           fallback_city_from_formatted_address(data)

    %{
      "name" => Map.get(data, "name", data["formatted_address"]),
      "formatted_address" => data["formatted_address"],
      "place_id" => Map.get(data, "place_id"),
      "location" => extract_location(data["geometry"]),
      "country" => components["country"],
      "city" => city,
      "state" => components["state"],
      "postal_code" => components["postal_code"]
    }
  end

  defp fallback_city_from_formatted_address(%{"formatted_address" => address}) when is_binary(address) do
    case String.split(address, ",") do
      [_street, city, _state | _] -> %{"name" => String.trim(city), "code" => nil}
      [_street, city | _] -> %{"name" => String.trim(city), "code" => nil}
      _ -> nil
    end
  end
  defp fallback_city_from_formatted_address(_), do: nil

  defp extract_address_components(components) when is_list(components) do
    %{
      "country" => extract_component(components, "country"),
      "city" => extract_component(components, "locality"),
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

  defp make_api_request(api_name, url, retries \\ 0) do
    case @http_client.get(url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} -> {:ok, response}
          {:error, error} ->
            Logger.error("Failed to decode #{api_name} API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("Google #{api_name} API HTTP #{status}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        if retries < @max_retries do
          Logger.warning("#{api_name} API request failed: #{inspect(error)}. Retry #{retries + 1}/#{@max_retries}")
          Process.sleep(@retry_wait_ms)
          make_api_request(api_name, url, retries + 1)
        else
          Logger.error("#{api_name} API request failed after #{@max_retries} retries: #{inspect(error)}")
          {:error, :over_query_limit}
        end
    end
  end

  defp retry_google_api(message, retries \\ 0) do
    if retries >= @max_retries do
      Logger.error("#{message}. Max retries (#{@max_retries}) exceeded.")
      {:error, :over_query_limit}
    else
      delay = @retry_wait_ms * :math.pow(2, retries) |> round()
      Logger.warning("#{message}. Retry #{retries + 1}/#{@max_retries} in #{delay}ms...")
      Process.sleep(delay)
      retry_google_api(message, retries + 1)
    end
  end

  defp has_required_fields?(data) do
    not is_nil(get_in(data, ["country", "name"])) and
    not is_nil(get_in(data, ["city", "name"]))
  end

  defp inspect_missing_fields(data) do
    required = ["country", "city"]
    missing = Enum.filter(required, fn field ->
      is_nil(get_in(data, [field, "name"]))
    end)

    """
    Missing fields: #{Enum.join(missing, ", ")}
    Data: #{inspect(data)}
    """
  end

  defp mask_api_key(url) do
    String.replace(url, ~r/([?&](?:key|apiKey|API_KEY|Key)=)[^&]+/, "\\1REDACTED")
  end
end

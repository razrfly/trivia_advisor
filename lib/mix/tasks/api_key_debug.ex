defmodule Mix.Tasks.ApiKeyDebug do
  @moduledoc """
  Mix task to debug Google API key issues with detailed information.

  ## Examples

      mix api_key_debug

  """

  use Mix.Task
  require Logger
  alias HTTPoison.Response

  @shortdoc "Debug Google API key with detailed info"

  def run(_args) do
    # Start required applications
    [:logger, :httpoison, :jason]
    |> Enum.each(&Application.ensure_all_started/1)

    # Load the API key from .env file
    api_key = load_api_key()

    # Check key format
    if is_nil(api_key) or api_key == "" do
      Logger.error("❌ Google API key not found in .env file")
      System.halt(1)
    end

    # Print key info safely
    key_prefix = String.slice(api_key, 0, 10)
    key_suffix = String.slice(api_key, -4, 4)
    key_length = String.length(api_key)
    Logger.info("🔑 Using API key: #{key_prefix}...#{key_suffix} (length: #{key_length})")

    # Test different endpoints
    test_google_maps_js_api(api_key)

    # Test both old and new Places API endpoints
    test_places_details_api_old(api_key)
    test_places_details_api_new(api_key)

    test_places_nearbysearch_api_old(api_key)
    test_places_nearbysearch_api_new(api_key)

    test_places_findplacefromtext_api_old(api_key)
    test_places_findplacefromtext_api_new(api_key)

    test_geocoding_api(api_key)
    test_static_maps_api(api_key)

    # Output usage recommendations
    Logger.info("\n🔧 Recommendations:")
    Logger.info("1. Check if this key is from the same project where Places API (New) is enabled")
    Logger.info("2. Verify billing is set up and active for this project")
    Logger.info("3. Check API key restrictions in Google Cloud Console")
    Logger.info("4. Try creating a new unrestricted API key for testing")
    Logger.info("5. If some APIs work but Places doesn't, specifically check Places API activation")
  end

  defp load_api_key do
    case File.read(".env") do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.find_value(fn line ->
          case String.split(line, "=", parts: 2) do
            ["GOOGLE_MAPS_API_KEY", value] -> String.trim(value)
            _ -> nil
          end
        end)
      _ -> nil
    end
  end

  defp test_google_maps_js_api(api_key) do
    Logger.info("\n🧪 Testing Google Maps JavaScript API...")
    url = "https://maps.googleapis.com/maps/api/js?key=#{api_key}&callback=initMap&v=weekly"

    case HTTPoison.get(url) do
      {:ok, %Response{status_code: 200}} ->
        Logger.info("✅ Google Maps JavaScript API is accessible")

      {:ok, %Response{status_code: code, body: body}} ->
        Logger.error("❌ Google Maps JavaScript API error: #{code}")
        log_error_details(body)

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  # Old Places API endpoints
  defp test_places_details_api_old(api_key) do
    Logger.info("\n🧪 Testing Places Details API (Standard version)...")
    # Sydney Opera House - well-known place
    place_id = "ChIJN1t_tDeuEmsRUsoyG83frY4"
    url = "https://maps.googleapis.com/maps/api/place/details/json?place_id=#{place_id}&fields=name&key=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)

        case response["status"] do
          "OK" ->
            place_name = get_in(response, ["result", "name"])
            Logger.info("✅ Places Details API (Standard) works - found place: #{place_name}")

          "REQUEST_DENIED" ->
            Logger.error("❌ Places Details API (Standard) request denied")
            log_error_details(body)

          status ->
            Logger.error("❌ Places Details API (Standard) error: #{status}")
            log_error_details(body)
        end

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  # New Places API endpoints
  defp test_places_details_api_new(api_key) do
    Logger.info("\n🧪 Testing Places Details API (New version)...")
    # Sydney Opera House - well-known place
    place_id = "ChIJN1t_tDeuEmsRUsoyG83frY4"
    url = "https://places.googleapis.com/v1/places/#{place_id}?key=#{api_key}"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", "displayName"}
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        place_name = get_in(response, ["displayName", "text"])
        Logger.info("✅ Places Details API (New) works - found place: #{place_name}")

      {:ok, %Response{status_code: code, body: body}} ->
        Logger.error("❌ Places Details API (New) error: #{code}")
        log_error_details(body)

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_places_nearbysearch_api_old(api_key) do
    Logger.info("\n🧪 Testing Places Nearby Search API (Standard version)...")
    # Sydney, Australia coordinates
    location = "-33.8670522,151.1957362"
    url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=#{location}&radius=500&key=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)

        case response["status"] do
          "OK" ->
            result_count = length(response["results"] || [])
            Logger.info("✅ Places Nearby Search API (Standard) works - found #{result_count} places")

          "REQUEST_DENIED" ->
            Logger.error("❌ Places Nearby Search API (Standard) request denied")
            log_error_details(body)

          status ->
            Logger.error("❌ Places Nearby Search API (Standard) error: #{status}")
            log_error_details(body)
        end

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_places_nearbysearch_api_new(api_key) do
    Logger.info("\n🧪 Testing Places Nearby Search API (New version)...")
    # Sydney, Australia coordinates
    _location = "-33.8670522,151.1957362"
    url = "https://places.googleapis.com/v1/places:searchNearby"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", "places.displayName"}
    ]

    body = Jason.encode!(%{
      "locationRestriction" => %{
        "circle" => %{
          "center" => %{
            "latitude" => -33.8670522,
            "longitude" => 151.1957362
          },
          "radius" => 500.0
        }
      }
    })

    case HTTPoison.post(url, body, headers) do
      {:ok, %Response{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        result_count = length(get_in(response, ["places"]) || [])
        Logger.info("✅ Places Nearby Search API (New) works - found #{result_count} places")

      {:ok, %Response{status_code: code, body: response_body}} ->
        Logger.error("❌ Places Nearby Search API (New) error: #{code}")
        log_error_details(response_body)

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_places_findplacefromtext_api_old(api_key) do
    Logger.info("\n🧪 Testing Places Find Place From Text API (Standard version)...")
    url = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=Sydney%20Opera%20House&inputtype=textquery&fields=name&key=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)

        case response["status"] do
          "OK" ->
            result_count = length(response["candidates"] || [])
            Logger.info("✅ Places Find Place API (Standard) works - found #{result_count} candidates")

          "REQUEST_DENIED" ->
            Logger.error("❌ Places Find Place API (Standard) request denied")
            log_error_details(body)

          status ->
            Logger.error("❌ Places Find Place API (Standard) error: #{status}")
            log_error_details(body)
        end

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_places_findplacefromtext_api_new(api_key) do
    Logger.info("\n🧪 Testing Places Find Place From Text API (New version)...")
    url = "https://places.googleapis.com/v1/places:searchText"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", "places.displayName"}
    ]

    body = Jason.encode!(%{
      "textQuery" => "Sydney Opera House"
    })

    case HTTPoison.post(url, body, headers) do
      {:ok, %Response{status_code: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        result_count = length(get_in(response, ["places"]) || [])
        Logger.info("✅ Places Find Place API (New) works - found #{result_count} places")

      {:ok, %Response{status_code: code, body: response_body}} ->
        Logger.error("❌ Places Find Place API (New) error: #{code}")
        log_error_details(response_body)

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_geocoding_api(api_key) do
    Logger.info("\n🧪 Testing Geocoding API...")
    url = "https://maps.googleapis.com/maps/api/geocode/json?address=Sydney%20Opera%20House&key=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)

        case response["status"] do
          "OK" ->
            result_count = length(response["results"] || [])
            Logger.info("✅ Geocoding API works - found #{result_count} results")

          "REQUEST_DENIED" ->
            Logger.error("❌ Geocoding API request denied")
            log_error_details(body)

          status ->
            Logger.error("❌ Geocoding API error: #{status}")
            log_error_details(body)
        end

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_static_maps_api(api_key) do
    Logger.info("\n🧪 Testing Static Maps API...")
    url = "https://maps.googleapis.com/maps/api/staticmap?center=Sydney&zoom=13&size=600x300&key=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %Response{status_code: 200}} ->
        Logger.info("✅ Static Maps API works")

      {:ok, %Response{status_code: code, body: body}} ->
        Logger.error("❌ Static Maps API error: #{code}")
        log_error_details(body)

      {:error, reason} ->
        Logger.error("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp log_error_details(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        error_message = get_in(data, ["error_message"]) || get_in(data, ["error", "message"]) || "Unknown error"
        status = get_in(data, ["status"]) || "Unknown status"
        Logger.error("  Status: #{status}")
        Logger.error("  Error message: #{error_message}")

        # Extract more detailed info if available
        if Map.has_key?(data, "error") do
          errors = get_in(data, ["error", "errors"]) || []
          Enum.each(errors, fn error ->
            reason = Map.get(error, "reason", "unknown")
            domain = Map.get(error, "domain", "unknown")
            Logger.error("  Error domain: #{domain}, reason: #{reason}")
          end)
        end

      _ ->
        Logger.error("  Could not parse error details: #{inspect(body)}")
    end
  end
end

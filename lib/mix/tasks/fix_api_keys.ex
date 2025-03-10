defmodule Mix.Tasks.FixApiKeys do
  @moduledoc """
  Mix task to explicitly set the Google Maps API key in the application environment.

  ## Examples

      mix fix_api_keys

  """

  use Mix.Task
  require Logger

  @shortdoc "Fix Google Maps API key configuration"
  @test_place_id "ChIJN1t_tDeuEmsRUsoyG83frY4" # Sydney Opera House - a well-known place ID

  def run(_args) do
    # Start required applications
    [:logger, :httpoison, :jason]
    |> Enum.each(&Application.ensure_all_started/1)

    # Load the API key from .env file directly
    api_key =
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

    if is_binary(api_key) and byte_size(api_key) > 0 do
      Logger.info("Found Google Maps API key in .env file")

      # Set it in the environment
      Logger.info("Setting GOOGLE_MAPS_API_KEY environment variable")
      System.put_env("GOOGLE_MAPS_API_KEY", api_key)

      # Also set it directly in the application config
      Logger.info("Setting application environment configuration")
      Application.put_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI, [google_maps_api_key: api_key])

      Logger.info("✅ API key configuration fixed")

      # Read back values to verify
      env_value = System.get_env("GOOGLE_MAPS_API_KEY")
      config_value = Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI)
      Logger.info("ENV value: #{if is_binary(env_value), do: String.slice(env_value, 0, 5) <> "...", else: "nil"}")
      Logger.info("CONFIG value: #{inspect(config_value)}")

      # Test all APIs and provide a summary
      test_results = test_all_apis(api_key)
      show_api_test_summary(test_results, api_key)
    else
      Logger.error("❌ Google Maps API key not found in .env file")
    end
  end

  defp test_all_apis(api_key) do
    Logger.info("\n🧪 Testing all Google APIs...")

    api_endpoints = [
      %{
        name: "Places API (Details)",
        url: "https://maps.googleapis.com/maps/api/place/details/json?place_id=#{@test_place_id}&fields=name&key=API_KEY",
        success_check: fn response -> response["status"] == "OK" end
      },
      %{
        name: "Geocoding API",
        url: "https://maps.googleapis.com/maps/api/geocode/json?address=Sydney+Opera+House&key=API_KEY",
        success_check: fn response -> response["status"] == "OK" end
      },
      %{
        name: "Maps Static API",
        url: "https://maps.googleapis.com/maps/api/staticmap?center=Sydney&zoom=13&size=600x300&key=API_KEY",
        success_check: fn _response -> true end, # Just check for 200 status
        response_type: :binary
      }
    ]

    api_endpoints
    |> Enum.map(fn endpoint ->
      url = String.replace(endpoint.url, "API_KEY", api_key)
      response_type = Map.get(endpoint, :response_type, :json)

      Logger.info("\n🔍 Testing #{endpoint.name}...")
      result = test_api_endpoint(url, endpoint, response_type)

      {endpoint.name, result}
    end)
  end

  defp test_api_endpoint(url, endpoint, response_type) do
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        if response_type == :binary do
          # For binary responses like images, just check status code
          Logger.info("✅ Success: Received 200 status code")
          {:ok, "Binary response (#{byte_size(body)} bytes)"}
        else
          # For JSON responses, check the specific API status
          response = Jason.decode!(body)

          if endpoint.success_check.(response) do
            Logger.info("✅ Success: API returned OK status")
            {:ok, response}
          else
            error_message = response["error_message"] || "Unknown error"
            status = response["status"] || "Unknown status"
            Logger.error("❌ API request returned non-OK status: #{status}")
            Logger.error("Error: #{error_message}")
            {:error, error_message}
          end
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        error_body = if response_type == :json, do: Jason.decode!(body), else: "Binary response"
        Logger.error("❌ HTTP error: #{status_code}")
        Logger.error("Response: #{inspect(error_body)}")
        {:error, "HTTP status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp show_api_test_summary(results, api_key) do
    Logger.info("\n📊 API TEST SUMMARY")
    Logger.info("-----------------")
    Logger.info("API Key: #{String.slice(api_key, 0, 8)}...")

    {successful, failed} =
      results
      |> Enum.split_with(fn {_, result} -> match?({:ok, _}, result) end)

    Logger.info("Successful APIs: #{length(successful)}/#{length(results)}")
    Logger.info("Failed APIs: #{length(failed)}/#{length(results)}")

    if length(failed) > 0 do
      Logger.info("\nFailed APIs:")
      failed
      |> Enum.each(fn {name, {:error, reason}} ->
        Logger.info("  ❌ #{name}: #{reason}")
      end)

      Logger.info("\nPossible issues:")
      Logger.info("1. API not enabled in Google Cloud Console")
      Logger.info("2. Billing not enabled for the project")
      Logger.info("3. API key has restrictions preventing use")
      Logger.info("4. API key belongs to a different project than where APIs are enabled")

      Logger.info("\nTo resolve:")
      Logger.info("1. Go to https://console.cloud.google.com/")
      Logger.info("2. Select the correct project")
      Logger.info("3. Navigate to 'APIs & Services' > 'Enabled APIs & services'")
      Logger.info("4. Ensure all needed APIs are enabled")
      Logger.info("5. Check 'APIs & Services' > 'Credentials' for API key restrictions")
      Logger.info("6. Ensure billing is enabled for the project")
    else
      Logger.info("\n✅ All APIs tested successfully!")
    end
  end
end

defmodule Mix.Tasks.TestVenueApi do
  @moduledoc """
  Mix task to test the Google Places API with a real venue from the database.

  ## Examples

      mix test_venue_api

  """

  use Mix.Task
  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue

  @shortdoc "Test Google Places API with a real venue"

  def run(_args) do
    # Start required applications
    [:logger, :httpoison, :jason, :postgrex, :ecto, :trivia_advisor]
    |> Enum.each(&Application.ensure_all_started/1)

    # Load the API key directly from .env
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

    if is_nil(api_key) or api_key == "" do
      Logger.error("❌ Google API key not found in .env file")
      System.halt(1)
    end

    # Set the API key in the environment
    System.put_env("GOOGLE_MAPS_API_KEY", api_key)
    Application.put_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI, [google_maps_api_key: api_key])

    Logger.info("Using API key: #{String.slice(api_key, 0, 8)}...")

    # Find a venue with a place_id
    venue = Repo.one(
      from v in Venue,
      where: not is_nil(v.place_id) and v.place_id != "",
      limit: 1
    )

    if is_nil(venue) do
      Logger.error("❌ No venue with place_id found in database")
      System.halt(1)
    end

    Logger.info("Testing with venue: #{venue.name}")
    Logger.info("Place ID: #{venue.place_id}")

    # Test the Places Details API
    test_place_details(venue.place_id, api_key)

    # Test the Place Photos API with a fake photo reference
    test_place_photos("FAKE_PHOTO_REFERENCE", api_key)
  end

  defp test_place_details(place_id, api_key) do
    Logger.info("\n🧪 Testing Google Places Details API...")
    url = "https://maps.googleapis.com/maps/api/place/details/json?place_id=#{place_id}&fields=name,photos&key=#{api_key}"

    Logger.info("Request URL: #{url}")

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)

        case response["status"] do
          "OK" ->
            Logger.info("✅ Places Details API is working!")
            place_name = get_in(response, ["result", "name"]) || "Unknown"
            photos_count = length(get_in(response, ["result", "photos"]) || [])
            Logger.info("Place name: #{place_name}")
            Logger.info("Photos available: #{photos_count}")

            # If we have photos, test the first one
            if photos_count > 0 do
              photo_ref = get_in(response, ["result", "photos", Access.at(0), "photo_reference"])
              test_place_photos(photo_ref, api_key)
            end

          "REQUEST_DENIED" ->
            Logger.error("❌ Places Details API request denied.")
            Logger.error("Error: #{response["error_message"]}")

          other_status ->
            Logger.error("❌ Places Details API test failed with status: #{other_status}")
            Logger.error("Response: #{inspect(response)}")
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("❌ HTTP error: #{status_code}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ HTTP request failed: #{inspect(reason)}")
    end
  end

  defp test_place_photos(photo_reference, api_key) do
    Logger.info("\n🧪 Testing Google Places Photos API...")
    url = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=#{photo_reference}&key=#{api_key}"

    Logger.info("Request URL pattern: https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=PHOTO_REF&key=API_KEY")

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.info("✅ Places Photos API is working!")

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        Logger.error("❌ Places Photos API permission denied (could be due to fake photo reference).")

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("❌ Places Photos API test failed with status: #{status_code}")
        Logger.error("Response: #{inspect(body)}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ HTTP request failed: #{inspect(reason)}")
    end
  end
end

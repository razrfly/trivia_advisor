defmodule Mix.Tasks.SyncVenueImages do
  @moduledoc """
  Mix task to sync Google Place images for all venues with place_ids.

  ## Examples

      mix sync_venue_images

  This will update all venues that have Google Place IDs with photo references.
  """

  use Mix.Task
  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @shortdoc "Sync Google Place images for all venues"
  @default_limit 10

  @impl Mix.Task
  def run(args) do
    # Parse command line options
    {opts, _, _} = OptionParser.parse(args,
      switches: [limit: :integer, fallback: :boolean],
      aliases: [l: :limit, f: :fallback]
    )

    limit = Keyword.get(opts, :limit, @default_limit)
    fallback = Keyword.get(opts, :fallback, false)

    # Start necessary applications
    [:postgrex, :ecto, :trivia_advisor]
    |> Enum.each(&Application.ensure_all_started/1)

    # Read API key from .env file or environment variables
    api_key = get_api_key_from_env_file() || System.get_env("GOOGLE_MAPS_API_KEY")

    if api_key && api_key != "" do
      Logger.info("✓ API key loaded successfully")
    else
      Logger.error("✗ Google Maps API key not configured")
    end

    # Test if Places API is working - specifically using Places API (New)
    force_fallback = fallback || !test_places_api_new(api_key)

    # If fallback mode is explicitly requested or the API test failed, use fallback mode
    if force_fallback do
      Logger.warning("⚠️ Using fallback mode due to Places API authorization issues")
      Logger.warning("   Images won't be fetched from Google, but venue records will be updated")

      # Get venues with place_id using Ecto query
      venues = Repo.all(
        from v in Venue,
        where: not is_nil(v.place_id) and v.place_id != "",
        limit: ^limit
      )

      Logger.info("Found #{length(venues)} venues to update")

      # Process each venue
      updated_count = venues
      |> Enum.map(fn venue ->
        Logger.info("Processing venue: #{venue.name}")

        case update_venue_with_fallback_images(venue) do
          {:ok, _updated_venue} ->
            Logger.info("✅ Successfully updated #{venue.name} with fallback image data")
            true
          {:error, reason} ->
            Logger.error("❌ Failed to update #{venue.name}: #{inspect(reason)}")
            false
        end
      end)
      |> Enum.count(& &1)

      # Summarize
      Logger.info("✅ Updated #{updated_count} out of #{length(venues)} venues")
      updated_count
    else
      # Normal mode - use Google Places API
      Logger.info("Using Google Places API to update venue images")

      # Get venues with place_id using Ecto query
      venues = Repo.all(
        from v in Venue,
        where: not is_nil(v.place_id) and v.place_id != "",
        limit: ^limit
      )

      Logger.info("Found #{length(venues)} venues to update")

      # Process each venue
      updated_count = venues
      |> Enum.map(fn venue ->
        Logger.info("Processing venue: #{venue.name}")

        case GooglePlaceImageStore.process_venue_images(venue) do
          {:ok, _updated_venue} ->
            Logger.info("✅ Successfully updated #{venue.name} with Google Place images")
            true
          {:error, reason} ->
            Logger.error("❌ Failed to update #{venue.name}: #{inspect(reason)}")
            false
        end
      end)
      |> Enum.count(& &1)

      # Summarize
      Logger.info("✅ Updated #{updated_count} out of #{length(venues)} venues")
      updated_count
    end
  end

  # Read API key from .env file
  defp get_api_key_from_env_file do
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

  # Test if the Places API (New) is working
  defp test_places_api_new(api_key) do
    Logger.info("Testing Places API...")

    if api_key && api_key != "" do
      # Test with a well-known place ID (Google Sydney)
      place_id = "ChIJN1t_tDeuEmsRUsoyG83frY4"
      url = "https://places.googleapis.com/v1/places/#{place_id}"

      headers = [
        {"Content-Type", "application/json"},
        {"X-Goog-Api-Key", api_key},
        {"X-Goog-FieldMask", "displayName"}
      ]

      case HTTPoison.get(url, headers, [timeout: 10000, recv_timeout: 10000]) do
        {:ok, %HTTPoison.Response{status_code: 200}} ->
          Logger.info("✓ Places API (New) is working")
          true

        {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              error_message = get_in(data, ["error", "message"]) || "Unknown error"
              Logger.error("❌ Places API authorization error: #{error_message}")
              false
            _ ->
              Logger.error("❌ Places API error: HTTP #{code}")
              false
          end

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("❌ Places API request failed: #{inspect(reason)}")
          false
      end
    else
      Logger.error("❌ Cannot test Places API: No API key available")
      false
    end
  end

  # Update venue with fallback images
  defp update_venue_with_fallback_images(venue) do
    # Create fallback data - 5 placeholder entries
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    image_data = Enum.map(1..5, fn position ->
      %{
        "fallback" => true,
        "fetched_at" => now,
        "place_id" => venue.place_id,
        "venue_id" => venue.id,
        "venue_name" => venue.name,
        "position" => position
      }
    end)

    # Update venue with fallback image data
    venue
    |> Venue.changeset(%{google_place_images: image_data})
    |> Repo.update()
  end
end

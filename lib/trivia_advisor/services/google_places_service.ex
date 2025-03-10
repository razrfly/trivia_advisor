defmodule TriviaAdvisor.Services.GooglePlacesService do
  @moduledoc """
  Service for fetching images from Google Places API.
  Uses Places API (New) for compatibility with Google Cloud Platform settings.
  """

  use GenServer
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue

  @max_images_per_venue 15

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Gets images for a venue directly from the Google Places API.
  Returns a list of image URLs.
  """
  def get_venue_images(venue_id) when is_binary(venue_id) or is_integer(venue_id) do
    case GenServer.call(__MODULE__, {:get_images, venue_id}) do
      {:ok, images} -> images
      {:error, _reason} -> []
    end
  end

  @doc """
  Gets a single image for a venue directly from the Google Places API.
  Returns a single image URL or nil.
  """
  def get_venue_image(venue_id) when is_binary(venue_id) or is_integer(venue_id) do
    case get_venue_images(venue_id) do
      [image | _] -> image
      _ -> nil
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    Logger.info("Starting GooglePlacesService")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_images, venue_id}, _from, state) do
    with {:ok, venue} <- get_venue(venue_id),
         true <- has_place_id?(venue) do

      # Fetch images directly from API
      case fetch_images_from_api(venue) do
        {:ok, images} ->
          {:reply, {:ok, images}, state}

        {:error, reason} ->
          Logger.error("Failed to fetch Google Places images: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to get venue for images: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
      false ->
        Logger.info("Venue #{venue_id} has no Google Place ID")
        {:reply, {:error, :no_place_id}, state}
    end
  end

  # Private functions

  defp get_venue(venue_id) do
    case Repo.get(Venue, venue_id) do
      nil -> {:error, :not_found}
      venue -> {:ok, venue}
    end
  end

  defp has_place_id?(venue) do
    venue.place_id != nil && venue.place_id != ""
  end

  defp fetch_images_from_api(venue) do
    api_key = get_google_api_key()

    if api_key == nil do
      # More detailed error message about API key
      Logger.error("Google API key not configured or empty")
      Logger.error("Value: #{inspect(api_key)}")
      Logger.error("Environment variable: #{inspect(System.get_env("GOOGLE_MAPS_API_KEY"))}")
      Logger.error("Application config: #{inspect(Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI))}")
      {:error, :no_api_key}
    else
      place_id = venue.place_id

      # Debug API key
      key_prefix = String.slice(api_key, 0, 10)
      key_suffix = String.slice(api_key, -4, 4)
      key_length = String.length(api_key)
      Logger.info("🔑 Using API key for venue #{venue.id}: #{key_prefix}...#{key_suffix} (length: #{key_length})")

      # Try both the Places API (New) and the standard Places API
      case try_places_api_new(place_id, api_key) do
        {:ok, photos} ->
          Logger.info("✅ Successfully fetched images using Places API (New) for venue #{venue.id}")
          {:ok, photos}

        {:error, reason} ->
          Logger.error("❌ Failed to fetch images using Places API (New): #{inspect(reason)}")
          Logger.info("⏭️ Falling back to standard Places API for venue #{venue.id}")

          # Fall back to standard Places API
          try_standard_places_api(place_id, api_key)
      end
    end
  end

  defp try_places_api_new(place_id, api_key) do
    # Using Places API (New) endpoint
    url = "https://places.googleapis.com/v1/places/#{place_id}"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", "photos"}
    ]

    Logger.debug("🌐 Calling Places API (New) with URL: #{url}")
    Logger.debug("🔐 Using headers: #{inspect(headers)}")

    case HTTPoison.get(url, headers, [timeout: 10000, recv_timeout: 10000]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        photos = get_photos_from_response_new(response, api_key)

        # Log success with photo count
        photo_count = length(photos)
        Logger.info("📸 Found #{photo_count} photos using Places API (New)")

        {:ok, photos}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.error("Google Places API rate limit reached")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        error_info = extract_error_info(body)
        Logger.error("Google Places API (New) error: #{status_code} - #{error_info}")
        Logger.debug("Response body: #{body}")
        {:error, "HTTP error: #{status_code} - #{error_info}"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp try_standard_places_api(place_id, api_key) do
    url = "https://maps.googleapis.com/maps/api/place/details/json?place_id=#{place_id}&fields=photos&key=#{api_key}"

    Logger.debug("🌐 Calling Standard Places API with URL: #{inspect(url)}")

    case HTTPoison.get(url, [], [timeout: 10000, recv_timeout: 10000]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)

        if response["status"] == "OK" do
          photos = get_photos_from_response_standard(response, api_key)

          # Log success with photo count
          photo_count = length(photos)
          Logger.info("📸 Found #{photo_count} photos using Standard Places API")

          {:ok, photos}
        else
          Logger.error("Google Places API error: #{response["status"]}")
          {:error, response["status"]}
        end

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.error("Google Places API rate limit reached")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        error_info = extract_error_info(body)
        Logger.error("Standard Places API error: #{status_code} - #{error_info}")
        Logger.debug("Response body: #{body}")
        {:error, "HTTP error: #{status_code} - #{error_info}"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp extract_error_info(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        error_message = get_in(data, ["error", "message"]) ||
                        get_in(data, ["error_message"]) ||
                        "Unknown error"
        error_message
      _ ->
        "Could not parse error response"
    end
  end

  defp get_photos_from_response_new(response, api_key) do
    photos = get_in(response, ["photos"]) || []

    photos
    |> Enum.take(@max_images_per_venue)
    |> Enum.map(fn photo ->
      # For Places API (New), we need to use the name field as the photo reference
      case get_in(photo, ["name"]) do
        nil -> nil
        photo_name ->
          # Extract just the ID part from the full photo name
          # The format is "places/PLACE_ID/photos/PHOTO_ID"
          case Regex.run(~r|places/[^/]+/photos/([^/]+)|, photo_name) do
            [_, _photo_id] ->
              # Documentation for maxHeightPx at:
              # https://developers.google.com/maps/documentation/places/web-service/photos#photo-media-type
              "https://places.googleapis.com/v1/#{photo_name}/media?key=#{api_key}&maxHeightPx=800"
            _ -> nil
          end
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_photos_from_response_standard(response, api_key) do
    photos = get_in(response, ["result", "photos"]) || []

    photos
    |> Enum.take(@max_images_per_venue)
    |> Enum.map(fn photo ->
      photo_reference = photo["photo_reference"]
      "https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=#{photo_reference}&key=#{api_key}"
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_google_api_key do
    # First try to get from .env file
    env_key = case File.read(".env") do
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

    env_var_key = System.get_env("GOOGLE_MAPS_API_KEY")
    config_key = Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI)[:google_maps_api_key]

    # Use the first non-empty key found
    cond do
      env_key && env_key != "" -> env_key
      env_var_key && env_var_key != "" -> env_var_key
      true -> config_key
    end
  end
end

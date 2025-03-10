defmodule TriviaAdvisor.Services.GooglePlacesService do
  @moduledoc """
  Service for fetching images from Google Places API.
  Now serves as a simple API client for the GooglePlaceImageStore, which handles
  permanent storage of images.
  """

  use GenServer
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue

  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)

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
      Logger.error("Google API key not configured")
      {:error, :no_api_key}
    else
      place_id = venue.place_id

      # Using the new Places API v2 endpoint for place details
      url = "https://places.googleapis.com/v1/places/#{place_id}"

      headers = [
        {"X-Goog-Api-Key", api_key},
        {"X-Goog-FieldMask", "photos,id,displayName,location"}
      ]

      case @http_client.get(url, headers, [timeout: 10000, recv_timeout: 10000]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          Logger.debug("Google Places API response: #{inspect(response)}")
          photos = get_photos_from_response(response, api_key, place_id)
          {:ok, photos}

        {:ok, %HTTPoison.Response{status_code: 429}} ->
          Logger.error("Google Places API rate limit reached")
          {:error, :rate_limited}

        {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
          error_message = extract_error_message(body)
          Logger.error("Google Places API error: HTTP #{status_code} - #{error_message}")
          {:error, "HTTP error: #{status_code} - #{error_message}"}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp extract_error_message(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} -> message
      {:ok, %{"error_message" => message}} -> message
      _ -> "Unknown error"
    end
  end

  defp get_photos_from_response(response, api_key, _place_id) do
    case get_in(response, ["photos"]) do
      photos when is_list(photos) and length(photos) > 0 ->
        # Instead of direct v2 photo URLs, we'll create media URLs using the photo reference
        # from the MediaLink's googleMapsUri field, which contains the photo reference
        Enum.map(photos, fn photo ->
          flag_content_uri = Map.get(photo, "flagContentUri")
          google_maps_uri = Map.get(photo, "googleMapsUri")

          photo_ref = extract_photo_reference_from_uri(flag_content_uri || google_maps_uri)

          if photo_ref do
            # Construct URL with the photo reference using the Places API Photo endpoint
            "https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=#{photo_ref}&key=#{api_key}"
          end
        end)
        |> Enum.filter(&(&1 != nil))
        |> Enum.take(5)  # Limit to 5 photos

      _ ->
        # Return empty list if no photos found
        []
    end
  end

  # Extract photo reference from URIs like:
  # "https://www.google.com/local/imagery/report/?cb_client=maps_api_places.places_api&image_key=!1e10!2sAF1QipPwqH7RJNC8LK4IFv5YtXHKb--3d81f4XLoMORD&hl=en-US"
  # or
  # "https://www.google.com/maps/place//data=!3m4!1e2!3m2!1sAF1QipPwqH7RJNC8LK4IFv5YtXHKb--3d81f4XLoMORD!2e10!4m2!3m1!1s0x47d8713644cb96fd:0x265918cb1f397890"
  defp extract_photo_reference_from_uri(uri) when is_binary(uri) do
    # Try to extract from image_key parameter
    case Regex.run(~r/image_key=!1e10!2s([^&]+)/, uri) do
      [_, photo_ref] -> photo_ref
      nil ->
        # Try to extract from the second format
        case Regex.run(~r/!3m2!1s([^!]+)!2e/, uri) do
          [_, photo_ref] -> photo_ref
          nil -> nil
        end
    end
  end

  defp extract_photo_reference_from_uri(_), do: nil

  defp get_google_api_key do
    # First try to get from environment variable directly
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 ->
        key
      _ ->
        # Fall back to application config
        Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI)[:google_maps_api_key]
    end
  end
end

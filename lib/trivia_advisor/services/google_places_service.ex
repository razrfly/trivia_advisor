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

  @max_images_per_venue 5

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

      url = "https://maps.googleapis.com/maps/api/place/details/json?place_id=#{place_id}&fields=photos&key=#{api_key}"

      case HTTPoison.get(url, [], [timeout: 10000, recv_timeout: 10000]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          response = Jason.decode!(body)

          if response["status"] == "OK" do
            photos = get_photos_from_response(response, api_key)
            {:ok, photos}
          else
            Logger.error("Google Places API error: #{response["status"]}")
            {:error, response["status"]}
          end

        {:ok, %HTTPoison.Response{status_code: 429}} ->
          Logger.error("Google Places API rate limit reached")
          {:error, :rate_limited}

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          {:error, "HTTP error: #{status_code}"}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp get_photos_from_response(response, api_key) do
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

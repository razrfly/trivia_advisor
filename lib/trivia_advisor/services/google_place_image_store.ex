defmodule TriviaAdvisor.Services.GooglePlaceImageStore do
  @moduledoc """
  Service for managing Google Place images for venues.
  This service:
  1. Fetches photo references from Google Places API (New)
  2. Stores them in the venue's google_place_images field
  3. Provides methods to construct image URLs dynamically
  """

  use GenServer
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Services.GooglePlacesService

  @max_images 15
  @refresh_days 90  # Number of days before considering refreshing venue images

  # Client API

  @doc """
  Start the GooglePlaceImageStore service
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Smart function to check if a venue should have its Google Place images updated
  and update them if needed. This is intended to be used by scrapers.

  It will only update images if:
  1. The venue has a place_id, and
  2. One of the following is true:
     a. The venue has no google_place_images
     b. The venue has fewer than 5 google_place_images
     c. The venue's images haven't been updated in at least 90 days

  Returns the venue (updated if images were fetched, or original if not)
  """
  def maybe_update_venue_images(venue) do
    if should_update_images?(venue) do
      Logger.info("🖼️ Fetching Google Place images for venue: #{venue.name}")

      try do
        case process_venue_images(venue) do
          {:ok, updated_venue} ->
            Logger.info("✅ Successfully fetched Google Place images for venue: #{venue.name}")
            updated_venue
          {:error, _reason} ->
            # Return the original venue on error
            venue
        end
      rescue
        e ->
          Logger.error("❌ Error fetching Google Place images: #{Exception.message(e)}")
          venue
      end
    else
      # Logger.debug("⏭️ Skipping Google Place images for venue: #{venue.name}")
      venue
    end
  end

  @doc """
  Determines if a venue should have its Google Place images updated
  based on defined criteria.
  """
  def should_update_images?(venue) do
    has_place_id?(venue) && (
      missing_or_few_images?(venue) ||
      images_need_refresh?(venue)
    )
  end

  @doc """
  Checks if a venue has a valid place_id.
  """
  def has_place_id?(venue) do
    Map.get(venue, :place_id) && venue.place_id != ""
  end

  @doc """
  Checks if a venue is missing images or has fewer than the max number.
  """
  def missing_or_few_images?(venue) do
    images = Map.get(venue, :google_place_images, [])
    is_nil(images) || length(images) < @max_images
  end

  @doc """
  Checks if a venue's images need to be refreshed based on the
  last update timestamp.
  """
  def images_need_refresh?(venue) do
    updated_at = Map.get(venue, :updated_at)

    if is_nil(updated_at) do
      true
    else
      days_since_update = DateTime.diff(DateTime.utc_now(), updated_at, :second) / 86400
      days_since_update > @refresh_days
    end
  end

  @doc """
  Processes Google Place images for a venue:
  1. Fetches photo_references from Google Places API
  2. Updates the venue's google_place_images field with photo_references

  Returns {:ok, venue} or {:error, reason}
  """
  def process_venue_images(venue_id) when is_integer(venue_id) or is_binary(venue_id) do
    venue = Repo.get(Venue, venue_id)
    if venue, do: process_venue_images(venue), else: {:error, :venue_not_found}
  end

  def process_venue_images(%Venue{} = venue) do
    # Skip if no place_id
    if venue.place_id && venue.place_id != "" do
      # Get images from Google Places API
      case GooglePlacesService.get_venue_images(venue.id) do
        [] ->
          Logger.info("No Google Place images found for venue #{venue.id}")
          {:ok, venue}

        images when is_list(images) ->
          # Process images (store references only)
          process_image_references(venue, images)

        _ ->
          {:error, :invalid_images}
      end
    else
      {:ok, venue}
    end
  end

  @doc """
  Returns the URLs for Google Place images for a venue.
  Constructs URLs dynamically from stored photo_references.

  Limits to the specified count (default 3), and randomizes the order.
  """
  def get_image_urls(venue, count \\ 3) do
    venue = ensure_loaded(venue)
    api_key = get_google_api_key()

    venue.google_place_images
    |> Enum.shuffle()  # Randomize the order of images
    |> Enum.take(count)
    |> Enum.map(fn image_data ->
      cond do
        # New format with photo_name (Places API New)
        Map.has_key?(image_data, "photo_name") && image_data["photo_name"] ->
          "https://places.googleapis.com/v1/#{image_data["photo_name"]}/media?key=#{api_key}&maxHeightPx=800"

        # Legacy format with photo_reference (old Places API)
        Map.has_key?(image_data, "photo_reference") && image_data["photo_reference"] ->
          "https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=#{image_data["photo_reference"]}&key=#{api_key}"

        # Very old formats for backward compatibility
        Map.has_key?(image_data, "local_path") && image_data["local_path"] ->
          ensure_full_url(image_data["local_path"])

        Map.has_key?(image_data, "original_url") && image_data["original_url"] ->
          image_data["original_url"]

        true ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns the first Google Place image URL for a venue, or nil if none exist.
  """
  def get_first_image_url(venue) do
    case get_image_urls(venue, 1) do
      [url | _] -> url
      _ -> nil
    end
  end

  @doc """
  Refreshes all venue Google Place images for maintenance purposes.
  Takes a limit parameter to control batch size.
  """
  def refresh_all_venue_images(max_venues \\ 100) do
    # Use a simpler approach without Ecto.Query macros for now
    venues = Repo.all("SELECT * FROM venues WHERE place_id IS NOT NULL AND place_id != '' LIMIT $1", [max_venues])

    {successful, failed} =
      venues
      |> Enum.map(fn venue ->
        case process_venue_images(venue) do
          {:ok, _} -> {:ok, venue.id}
          error -> {venue.id, error}
        end
      end)
      |> Enum.split_with(fn
        {:ok, _} -> true
        _ -> false
      end)

    %{
      processed: length(venues),
      successful: length(successful),
      failed: length(failed),
      failed_ids: Enum.map(failed, fn {id, _} -> id end)
    }
  end

  @doc """
  This is now a no-op since we no longer store physical files.
  Kept for backward compatibility.
  """
  def delete_venue_images(_venue), do: :ok

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting GooglePlaceImageStore")
    {:ok, %{}}
  end

  # Private functions

  defp process_image_references(venue, image_urls) do
    # Limit to max images
    image_urls = Enum.take(image_urls, @max_images)

    # Extract photo references from each URL
    image_data =
      image_urls
      |> Enum.with_index(1)
      |> Enum.map(fn {url, position} ->
        cond do
          # Handle new Places API (New) URLs
          String.contains?(url, "places.googleapis.com/v1/") ->
            extract_photo_name(url, position)

          # Handle old Places API URLs
          String.contains?(url, "photoreference=") ->
            extract_photo_reference(url, position)

          # Skip invalid URLs
          true ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Update venue with new image data
    update_venue_with_images(venue, image_data)
  end

  defp extract_photo_name(url, position) do
    # For Places API (New), extract the photo name from URL
    # Format: https://places.googleapis.com/v1/places/PLACE_ID/photos/PHOTO_ID/media?key=API_KEY&maxHeightPx=800
    case Regex.run(~r|v1/(places/[^/]+/photos/[^/]+)/media|, url) do
      [_, photo_name] ->
        %{
          "photo_name" => photo_name,
          "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "position" => position
        }
      _ -> nil
    end
  end

  defp extract_photo_reference(url, position) do
    # For old Places API, extract the photo reference from URL
    case Regex.run(~r/photoreference=([^&]+)/, url) do
      [_, photo_ref] ->
        %{
          "photo_reference" => photo_ref,
          "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "position" => position
        }
      _ -> nil
    end
  end

  defp update_venue_with_images(venue, image_data) when is_list(image_data) do
    if Enum.any?(image_data) do
      # Update venue with new image data
      venue
      |> Venue.changeset(%{google_place_images: image_data})
      |> Repo.update()
    else
      # No images to update
      {:ok, venue}
    end
  end

  defp ensure_loaded(%Venue{google_place_images: images} = venue) when is_list(images), do: venue
  defp ensure_loaded(%Venue{} = venue), do: Repo.reload(venue)
  defp ensure_loaded(venue_id) when is_integer(venue_id) or is_binary(venue_id) do
    Repo.get(Venue, venue_id)
  end

  defp ensure_full_url(path) do
    if String.starts_with?(path, "http") do
      path
    else
      # Add the static path prefix if needed
      if String.starts_with?(path, "/") do
        path
      else
        "/#{path}"
      end
    end
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

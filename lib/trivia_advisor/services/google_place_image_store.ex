defmodule TriviaAdvisor.Services.GooglePlaceImageStore do
  @moduledoc """
  Service for downloading, storing, and managing Google Place images for venues.
  This service:
  1. Fetches photo references from Google Places API (New)
  2. Downloads images from Google Places API
  3. Stores them physically using Waffle
  4. Updates the venue's google_place_images field with metadata
  """

  use GenServer
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Uploaders.GooglePlaceImage
  alias TriviaAdvisor.Services.GooglePlacesService

  @max_images 5  # Store top 5 images per venue
  @refresh_days 90  # Number of days before considering refreshing venue images
  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)

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
      Logger.info("""
      🖼️ Updating Google Place images for venue: #{venue.name}
      - place_id: #{venue.place_id}
      - existing images: #{length(venue.google_place_images)}
      - last updated: #{venue.updated_at}
      """)

      try do
        case process_venue_images(venue) do
          {:ok, updated_venue} ->
            Logger.info("""
            ✅ Successfully updated Google Place images for venue: #{venue.name}
            - place_id: #{venue.place_id}
            - image count: #{length(updated_venue.google_place_images)}
            """)
            updated_venue
          {:error, reason} ->
            # Log the error
            Logger.error("❌ Error updating Google Place images: #{inspect(reason)}")
            # Return the original venue on error
            venue
        end
      rescue
        e ->
          Logger.error("❌ Error fetching Google Place images: #{Exception.message(e)}")
          venue
      end
    else
      # For better debugging, log why we're skipping
      cond do
        not has_place_id?(venue) ->
          Logger.debug("⏭️ Skipping image update for #{venue.name}: No place_id")
        not missing_or_few_images?(venue) ->
          Logger.debug("⏭️ Skipping image update for #{venue.name}: Already has #{length(venue.google_place_images)} images")
        not images_need_refresh?(venue) ->
          Logger.debug("⏭️ Skipping image update for #{venue.name}: Images are recent (updated at #{venue.updated_at})")
        true ->
          Logger.debug("⏭️ Skipping image update for #{venue.name}: Unknown reason")
      end
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
  1. Fetches images from Google Places API
  2. Downloads and stores them physically
  3. Updates the venue's google_place_images field with metadata

  Returns {:ok, venue} or {:error, reason}
  """
  def process_venue_images(venue_id) when is_integer(venue_id) or is_binary(venue_id) do
    venue = Repo.get(Venue, venue_id)
    if venue, do: process_venue_images(venue), else: {:error, :venue_not_found}
  end

  def process_venue_images(%Venue{} = venue) do
    # Skip if no place_id
    if venue.place_id && venue.place_id != "" do
      Logger.info("🔄 Processing Google Place images for venue #{venue.id} (#{venue.name})")

      # Get images from Google Places API
      case GooglePlacesService.get_venue_images(venue.id) do
        [] ->
          Logger.info("ℹ️ No Google Place images found for venue #{venue.id}")
          {:ok, venue}

        {:error, :rate_limited} ->
          Logger.warning("⚠️ Rate limited when fetching images for venue #{venue.id}")
          {:error, :rate_limited}

        {:error, reason} ->
          Logger.error("❌ Error fetching images: #{inspect(reason)}")
          {:error, reason}

        images when is_list(images) ->
          Logger.info("✅ Got #{length(images)} images from Google Places API for venue #{venue.id}")

          # Process images (download, store, update venue)
          try do
            case process_image_list(venue, images) do
              {:ok, updated_venue} ->
                Logger.info("✅ Successfully processed images for venue #{venue.id}")
                {:ok, updated_venue}

              # If image processing fails, at least store the image URLs
              {:error, reason} ->
                Logger.warning("⚠️ Image processing failed: #{inspect(reason)}, storing URLs instead")
                store_image_urls_in_venue(venue, images)
            end
          rescue
            e ->
              Logger.error("❌ Exception processing images: #{Exception.message(e)}")
              {:error, {:exception, e}}
          end

        other ->
          Logger.error("❌ Unexpected response from GooglePlacesService: #{inspect(other)}")
          {:error, :invalid_images}
      end
    else
      Logger.debug("⏭️ Skipping venue #{venue.id}: No place_id")
      {:ok, venue}
    end
  end

  @doc """
  Returns the URLs for stored Google Place images for a venue.

  Limits to the specified count (default 3), and orders by position.
  """
  def get_image_urls(venue, count \\ 3) do
    venue = ensure_loaded(venue)

    venue.google_place_images
    |> Enum.sort_by(& &1["position"], :asc)
    |> Enum.take(count)
    |> Enum.map(fn image_data ->
      # Prefer local URL if available
      if image_data["local_path"] do
        ensure_full_url(image_data["local_path"])
      else
        Logger.warning("⚠️ Image for venue #{venue.id} (#{venue.name}) missing local_path, falling back to original_url")
        image_data["original_url"]
      end
    end)
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
  Deletes all Google Place images for a venue from the filesystem.
  This function is meant to be called from a before_delete callback.

  Returns :ok on success, or {:error, reason} on failure.
  """
  def delete_venue_images(%Venue{google_place_images: images, slug: slug, id: venue_id} = venue) when is_list(images) and length(images) > 0 do
    Logger.info("🗑️ Deleting Google Place images for venue: #{venue.name}")
    Logger.info("🔍 Image data: #{inspect(images)}")

    # Track successes
    Enum.each(images, fn image ->
      position = image["position"] || 0
      # Create the scope that matches what was used when storing
      scope = {venue_id, slug, position}

      # We need to try to delete both the original and thumb versions
      versions = [:original, :thumb]

      Enum.each(versions, fn version ->
        # Generate filename - must match the format in the uploader
        filename = "#{version}_google_place_#{position}"

        # Try to delete the file using Waffle
        try do
          # First try using direct file deletion
          if image["local_path"] do
            # Extract the path from the database
            local_path = image["local_path"]

            # Apply different path resolution approaches
            paths_to_try = [
              # Approach 1: The path as stored in the database
              Path.join([Application.app_dir(:trivia_advisor), "priv/static", local_path]),

              # Approach 2: Directly use the full path when the local_path already includes priv/static
              local_path,

              # Approach 3: Try uploads directory in priv/static
              Path.join([Application.app_dir(:trivia_advisor), "priv/static/uploads/google_place_images", "#{slug}/#{filename}.jpg"]),

              # Approach 4: Try uploads directory without app_dir (for dev environment)
              Path.join(["priv/static", local_path])
            ]

            # Try each path
            deleted = Enum.reduce_while(paths_to_try, false, fn path, _acc ->
              Logger.info("🔍 Attempting to delete file at path: #{path}")

              if File.exists?(path) do
                File.rm!(path)
                Logger.info("✅ Successfully deleted image: #{path}")
                {:halt, true}  # Stop trying other paths
              else
                {:cont, false}  # Continue to next path
              end
            end)

            # Log if we couldn't find the file in any location
            unless deleted do
              Logger.warning("⚠️ File not found at any standard path, tried: #{inspect(paths_to_try)}")
            end
          else
            # Fallback to Waffle if no local_path
            Logger.info("🔍 No local_path in image data, falling back to Waffle")
            GooglePlaceImage.delete({filename, scope})
            Logger.info("✅ Deleted image with Waffle: #{filename}")
          end
        rescue
          e ->
            Logger.warning("⚠️ Failed to delete image #{filename}: #{inspect(e)}")
        end
      end)
    end)

    # Delete empty directories - try both with and without app_dir
    delete_empty_directories(venue.slug)

    Logger.info("✅ Successfully deleted all Google Place images for venue: #{venue.name}")
    :ok
  end

  # No images to delete, but still try to delete empty directories
  def delete_venue_images(%Venue{slug: slug} = venue) when not is_nil(slug) do
    Logger.info("🗑️ No Google Place images to delete for venue: #{venue.name}, but cleaning up directories")
    delete_empty_directories(venue.slug)
    :ok
  end

  # Fallback for nil cases
  def delete_venue_images(_venue), do: :ok

  # Helper to delete empty directories for a venue by slug
  defp delete_empty_directories(slug) when is_binary(slug) do
    # Define all possible paths where venue directories might exist
    directory_paths = [
      # Google place images directories
      Path.join([Application.app_dir(:trivia_advisor), "priv/static/uploads/google_place_images", slug]),
      Path.join(["priv/static/uploads/google_place_images", slug]),

      # Regular venue images directories
      Path.join([Application.app_dir(:trivia_advisor), "priv/static/uploads/venues", slug]),
      Path.join(["priv/static/uploads/venues", slug])
    ]

    # Try to delete each directory if it exists and is empty
    Enum.each(directory_paths, fn dir_path ->
      try do
        if File.exists?(dir_path) do
          case File.ls(dir_path) do
            {:ok, []} ->
              # Directory exists and is empty
              File.rmdir(dir_path)
              Logger.info("✅ Deleted empty directory: #{dir_path}")

            {:ok, files} ->
              # Directory exists and has files - attempt to delete them all
              Logger.info("🔍 Found #{length(files)} remaining files in: #{dir_path}")

              # Delete each file in the directory
              Enum.each(files, fn file ->
                file_path = Path.join(dir_path, file)
                if File.exists?(file_path) && not File.dir?(file_path) do
                  File.rm!(file_path)
                  Logger.info("✅ Deleted remaining file: #{file_path}")
                end
              end)

              # Try to delete directory again after emptying
              case File.ls(dir_path) do
                {:ok, []} ->
                  File.rmdir(dir_path)
                  Logger.info("✅ Deleted directory after emptying: #{dir_path}")
                _ ->
                  Logger.warning("⚠️ Directory still not empty after cleanup: #{dir_path}")
              end

            {:error, reason} ->
              Logger.warning("⚠️ Could not read directory #{dir_path}: #{inspect(reason)}")
          end
        end
      rescue
        e ->
          Logger.warning("⚠️ Error while trying to delete directory #{dir_path}: #{inspect(e)}")
      end
    end)
  end

  defp delete_empty_directories(_), do: :ok

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting GooglePlaceImageStore")
    {:ok, %{}}
  end

  # Private functions

  defp process_image_list(venue, image_urls) do
    # Limit to max images
    image_urls = Enum.take(image_urls, @max_images)

    Logger.info("🔄 Processing #{length(image_urls)} images for venue #{venue.id} (#{venue.name})")

    # Download and process each image with a position
    image_results =
      image_urls
      |> Enum.with_index(1)
      |> Enum.map(fn {url, position} ->
        try do
          # Add a slight delay between downloads (0.5-1.5 seconds)
          # to avoid overwhelming the server
          random_delay = :rand.uniform(1000) + 500
          Process.sleep(random_delay)

          Logger.debug("📥 Processing image #{position}/#{length(image_urls)} for venue #{venue.id}")
          process_single_image(venue, url, position)
        rescue
          e ->
            Logger.error("❌ Exception processing image #{position}: #{Exception.message(e)}")
            {:error, {:exception, e}}
        end
      end)
      |> Enum.filter(fn
        %{} = result when is_map(result) -> true  # Keep successful results
        {:error, _} -> false  # Filter out errors
      end)

    # Update venue with new image data or return error if all failed
    if Enum.any?(image_results) do
      Logger.info("✅ Successfully processed #{length(image_results)} images for venue #{venue.id}")
      update_venue_with_images(venue, image_results)
    else
      # If all images failed, try to store just the URLs as a fallback
      Logger.warning("⚠️ All images failed processing for venue #{venue.id}, storing URLs instead")
      store_image_urls_in_venue(venue, image_urls)
    end
  end

  defp process_single_image(venue, url, position) do
    photo_ref = extract_photo_reference_from_url(url)

    if photo_ref do
      case download_image(url) do
        {:ok, image_file} ->
          # Store image using Waffle
          scope = {venue.id, venue.slug, position}

          case upload_image(image_file, scope) do
            {:ok, filename} ->
              # Return successful image data - focusing on local_path rather than original_url
              %{
                "google_ref" => photo_ref,
                "local_path" => filename,
                "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
                "position" => position
              }

            {:error, reason} ->
              Logger.error("Failed to upload Google Place image: #{inspect(reason)}")
              {:error, :upload_failed}
          end

        {:error, reason} ->
          Logger.error("Failed to download Google Place image: #{inspect(reason)}")
          {:error, :download_failed}
      end
    else
      {:error, :invalid_url}
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

  defp download_image(url) do
    Logger.info("📥 Downloading Google Place image: #{url}")

    headers = [
      {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
      {"Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"},
      {"Referer", "https://www.google.com/"}
    ]

    # If the URL is from the Places API v2 (contains places.googleapis.com/v1),
    # then use the API key in the URL rather than adding it to the headers
    {url_for_request, headers_for_request, options} =
      if String.contains?(url, "places.googleapis.com/v1") do
        # Keep the key in the URL and use the right options for the new API
        {url, headers, [follow_redirect: true, recv_timeout: 15000]}
      else
        # For the old API, keep using the existing approach
        {url, headers, [follow_redirect: true, recv_timeout: 15000]}
      end

    # Test if the URL looks valid
    if not String.starts_with?(url_for_request, "http") do
      Logger.error("❌ Invalid URL format: #{url_for_request}")
      {:error, :invalid_url_format}
    else
      case @http_client.get(url_for_request, headers_for_request, options) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          # Check if we got a valid image (non-empty body)
          if byte_size(body) > 100 do
            # Create temp file with a random name and jpg extension
            filename = "google_place_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}.jpg"
            temp_path = Path.join(System.tmp_dir!(), filename)

            with :ok <- File.write(temp_path, body) do
              Logger.info("✅ Successfully downloaded image to: #{temp_path}")
              {:ok, %{path: temp_path, file_name: filename, content_type: "image/jpeg"}}
            else
              error ->
                Logger.error("❌ Failed to write Google Place image to disk: #{inspect(error)}")
                {:error, :file_write_failed}
            end
          else
            Logger.error("❌ Empty or invalid image returned (body size: #{byte_size(body)} bytes)")
            {:error, :invalid_image_data}
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          Logger.error("❌ Failed to download Google Place image, status code: #{status}")
          {:error, "HTTP error: #{status}"}

        {:error, %HTTPoison.Error{reason: reason} = error} ->
          Logger.error("❌ HTTP request error: #{inspect(error)}")
          {:error, reason}

        error ->
          Logger.error("❌ Unexpected error when downloading image: #{inspect(error)}")
          {:error, :unknown_error}
      end
    end
  end

  defp upload_image(image_file, scope) do
    try do
      # First ensure we have a valid image_file map
      if is_nil(image_file) do
        Logger.error("❌ Image file is nil")
        raise "Image file cannot be nil"
      end

      # Convert image_file to Plug.Upload format that Waffle expects
      upload = if is_map(image_file) and Map.has_key?(image_file, :path) do
        # Already in the right format
        %Plug.Upload{
          path: image_file.path || "",
          filename: image_file.file_name || "image.jpg",
          content_type: image_file.content_type || "image/jpeg"
        }
      else
        # Convert to expected format
        %Plug.Upload{
          path: image_file[:path] || image_file["path"] || "",
          filename: image_file[:file_name] || image_file["file_name"] || "image.jpg",
          content_type: image_file[:content_type] || image_file["content_type"] || "image/jpeg"
        }
      end

      # Validate that we have a valid path
      if upload.path == "" or !File.exists?(upload.path) do
        Logger.error("❌ Invalid or missing file path: #{inspect(upload.path)}")
        raise "Invalid or missing file path"
      end

      # Log what we're uploading for debugging
      Logger.debug("""
      📤 Uploading image:
        Path: #{upload.path}
        Filename: #{upload.filename}
        Content-Type: #{upload.content_type}
        Scope: #{inspect(scope)}
      """)

      # Store the file using Waffle
      case GooglePlaceImage.store({upload, scope}) do
        {:ok, filename} ->
          # Better handling of filename types
          filename_str = case filename do
            bin when is_binary(bin) -> bin
            atom when is_atom(atom) -> Atom.to_string(atom)
            list when is_list(list) ->
              if List.ascii_printable?(list), do: List.to_string(list), else: inspect(list)
            other ->
              Logger.warning("⚠️ Unexpected filename type: #{inspect(other)}", [])
              inspect(other)
          end

          # Get URL path for the file
          path = GooglePlaceImage.url({filename_str, scope}, :original)

          # Strip the /priv/static prefix if it exists
          path = String.replace(path, ~r{^/priv/static}, "")
          Logger.info("✅ Successfully uploaded image to: #{path}")
          {:ok, path}

        error ->
          Logger.error("❌ Waffle upload failed: #{inspect(error)}")
          {:error, error}
      end
    rescue
      e ->
        Logger.error("❌ Exception during image upload: #{Exception.message(e)}")
        {:error, :upload_exception}
    end
  end

  # Extract photo reference from URL
  defp extract_photo_reference_from_url(url) do
    cond do
      # For Places API (New) URLs - photos:getFullSizeImage endpoint
      String.contains?(url, "photos:getFullSizeImage") ->
        case Regex.run(~r/photoreference=([^&]+)/, url) do
          [_, photo_ref] -> photo_ref
          _ -> nil
        end

      # For Places API (New) URLs - places/{place_id}/photos/{photo_id}/media endpoint
      String.contains?(url, "/photos/") && String.contains?(url, "/media") ->
        case Regex.run(~r{/photos/([^/]+)/media}, url) do
          [_, photo_id] -> photo_id
          _ -> nil
        end

      # For Google Maps CDN URL format (PhotoService.GetPhoto)
      String.contains?(url, "PhotoService.GetPhoto") ->
        case Regex.run(~r/1s([^&]+)/, url) do
          [_, photo_id] -> photo_id
          _ -> nil
        end

      # For standard Places API
      true ->
        case Regex.run(~r/photoreference=([^&]+)/, url) do
          [_, photo_ref] -> photo_ref
          _ -> nil
        end
    end
  end

  defp ensure_loaded(%Venue{google_place_images: images} = venue) when is_list(images), do: venue
  defp ensure_loaded(%Venue{} = venue), do: Repo.reload(venue)
  defp ensure_loaded(venue_id) when is_integer(venue_id) or is_binary(venue_id) do
    Repo.get(Venue, venue_id)
  end

  defp ensure_full_url(path) do
    # Return a default image if path is nil or not a binary
    if is_nil(path) or not is_binary(path) do
      "https://placehold.co/600x400/png"
    else
      try do
        cond do
          # Already a full URL
          String.starts_with?(path, "http") ->
            path

          # Check if using S3 storage in production
          Application.get_env(:waffle, :storage) == Waffle.Storage.S3 ->
            # Get S3 configuration
            s3_config = Application.get_env(:ex_aws, :s3, [])
            bucket = Application.get_env(:waffle, :bucket, "trivia-app")

            # For Tigris S3-compatible storage, we need to use a public URL pattern
            # that doesn't rely on object ACLs
            host = case s3_config[:host] do
              h when is_binary(h) -> h
              _ -> "fly.storage.tigris.dev"
            end

            # Format path correctly for S3 (remove leading slash)
            s3_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path

            # Construct the full S3 URL
            # Using direct virtual host style URL
            "https://#{bucket}.#{host}/#{s3_path}"

          # Local development
          true ->
            # Use endpoint URL to construct full URL for local environment
            endpoint_url =
              try do
                TriviaAdvisorWeb.Endpoint.url()
              rescue
                # If endpoint not available (e.g. in test environment)
                _ -> "http://localhost:4000"
              end

            if String.starts_with?(path, "/") do
              "#{endpoint_url}#{path}"
            else
              "#{endpoint_url}/#{path}"
            end
        end
      rescue
        e ->
          Logger.error("Error constructing URL from path #{inspect(path)}: #{Exception.message(e)}")
          "https://placehold.co/600x400/png"
      end
    end
  end

  # Store images by downloading them from URLs and storing locally
  defp store_image_urls_in_venue(venue, image_urls) do
    Logger.info("📝 Attempting to download and store #{length(image_urls)} images for venue #{venue.id}")

    # Try to download each image and store locally
    image_data =
      image_urls
      |> Enum.with_index(1)
      |> Enum.map(fn {url, position} ->
        # Try to actually download and store the image
        result = process_single_image(venue, url, position)

        # If successful, use the result with local_path
        # Otherwise fall back to just storing the URL
        case result do
          %{} = image when is_map(image) ->
            Logger.info("✅ Successfully downloaded and stored image #{position} for venue #{venue.id}")
            image
          _ ->
            Logger.warning("⚠️ Failed to download image #{position}, storing URL reference only")
            %{
              "google_ref" => extract_photo_reference_from_url(url),
              "original_url" => url,
              "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "position" => position
            }
        end
      end)

    # Update venue with new image data
    venue
    |> Venue.changeset(%{google_place_images: image_data})
    |> Repo.update()
  end
end

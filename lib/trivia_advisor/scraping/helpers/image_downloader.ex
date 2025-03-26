defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  @moduledoc """
  Helper module for downloading images from URLs.
  Provides centralized functionality for image downloading across scrapers.

  Note: There are other image downloading functions in the codebase:
  - VenueHelpers.download_image - Used for venue-related images, returns {:ok, map} tuples
  - GooglePlaceImageStore.download_image - Specialized for Google Place images with specific headers

  This module exists to handle image downloading with a unified interface
  that returns a format compatible with Waffle attachments.
  """

  require Logger

  @doc """
  Downloads an image from a URL and returns a file struct compatible with Waffle.

  ## Parameters
    - url: The URL of the image to download
    - prefix: Optional prefix for the temporary filename (default: "image")
    - force_refresh: When true, will download the image regardless of whether it exists already

  ## Returns
    - A file struct with `filename` and `path` keys if successful
    - `nil` if the download fails

  ## Example
      ImageDownloader.download_image("https://example.com/image.jpg", "performer")
      # => %{filename: "performer_123456.jpg", path: "/tmp/performer_123456.jpg"}
  """
  def download_image(url, prefix \\ "image", force_refresh \\ false) when is_binary(url) do
    # CRITICAL FIX: Handle nil case for force_refresh - if nil, use false as the default
    # This avoids errors when force_refresh is nil from Process.get
    force_refresh = if is_nil(force_refresh), do: false, else: force_refresh

    # Log force_refresh parameter for debugging
    Logger.info("📥 Downloading image from URL: #{url}, force_refresh: #{inspect(force_refresh)}")

    # Get temporary directory for file
    tmp_dir = System.tmp_dir!()

    # Determine the file extension from the URL or content type
    extension = case URI.parse(url) |> Map.get(:path) do
      nil ->
        Logger.debug("No path in URL, using default extension .jpg")
        ".jpg"
      path ->
        ext = Path.extname(path)
        if ext == "" do
          Logger.debug("No extension in URL path, will try to detect from content type")
          detect_extension_from_url(url)
        else
          Logger.debug("Using extension from URL path: #{ext}")
          ext
        end
    end

    # Get a normalized version of the original filename if we can extract it
    original_filename = url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
    |> normalize_filename()

    # Determine the filename to use
    filename = cond do
      # If prefix contains the original filename already, just use it directly
      prefix == original_filename ->
        original_filename

      # If prefix contains underscores (indicating it's already a consistent filename)
      String.contains?(prefix, "_") ->
        prefix

      # Use the original filename if available
      original_filename != "" ->
        original_filename

      # Fallback to a generated name with prefix
      true ->
        hash = :crypto.strong_rand_bytes(16) |> Base.encode16()
        "#{prefix}_#{hash}#{extension}"
    end

    # Create full path for downloaded file
    path = Path.join(tmp_dir, filename)

    Logger.debug("📄 Will save image to: #{path}")

    # IMPORTANT: Delete the file first if force_refresh is true, then continue with normal logic
    # This ensures we actually get a fresh copy when force_refresh=true
    if force_refresh and File.exists?(path) do
      Logger.info("🔄 Force refreshing existing image at #{path} because force_refresh=#{inspect(force_refresh)}")
      # Delete the existing file to ensure we download a fresh copy
      File.rm!(path)
      Logger.info("🗑️ Deleted existing image to force refresh")
    end

    # Now proceed with normal logic (which is correct since we've already deleted the file if needed)
    if File.exists?(path) and not force_refresh do
      Logger.info("✅ Image already exists at #{path} (skipping download)")
      %{filename: filename, path: path}
    else
      # Log why we're downloading
      if not File.exists?(path) do
        Logger.info("🔄 Downloading new image because file doesn't exist")
      end

      # Do the actual download
      case download_file(url, path) do
        {:ok, _} ->
          Logger.debug("✅ Successfully downloaded image to #{path}")
          %{filename: filename, path: path}

        {:error, reason} ->
          Logger.error("❌ Failed to download image: #{inspect(reason)}")
          nil
      end
    end
  end

  @doc """
  Normalize a filename according to consistent rules:
  - Spaces converted to dashes (-)
  - URL-encoded characters decoded and formatted properly
  - Query parameters stripped (everything after ? removed)
  - Double dashes (--) reduced to single dash (-)
  - Consistent case handling (lowercase)

  ## Parameters
    - filename: The original filename to normalize

  ## Returns
    - Normalized filename string

  ## Example
      normalize_filename("image%20with%20spaces.jpg?12345")
      # => "image-with-spaces.jpg"
  """
  def normalize_filename(filename) when is_binary(filename) do
    filename
    |> URI.decode() # Decode URL-encoded characters
    |> String.split("?") |> List.first() # Remove query parameters
    |> String.replace(~r/\s+/, "-") # Replace spaces with dashes
    |> String.replace(~r/\%20|\+/, "-") # Replace %20 or + with dash
    |> String.replace(~r/-+/, "-") # Replace multiple dashes with single dash
    |> String.downcase() # Ensure consistent case
  end
  def normalize_filename(nil), do: ""
  def normalize_filename(_), do: ""

  # Attempt to detect file extension from URL or headers
  defp detect_extension_from_url(url) do
    case HTTPoison.head(url, [], follow_redirect: true, max_redirects: 5) do
      {:ok, %{status_code: 200, headers: headers}} ->
        case get_content_type(headers) do
          nil -> ".jpg"  # Default to jpg if we can't detect
          content_type ->
            ext = extension_from_content_type(content_type)
            Logger.debug("Using detected extension for image without extension")
            ext
        end
      _ ->
        ".jpg"  # Default to jpg if HEAD request fails
    end
  end

  # Extract content-type from headers
  defp get_content_type(headers) do
    Enum.find_value(headers, fn
      {"Content-Type", value} -> value
      {"content-type", value} -> value
      _ -> nil
    end)
  end

  # Map content type to file extension
  defp extension_from_content_type(content_type) do
    cond do
      String.contains?(content_type, "image/jpeg") -> ".jpg"
      String.contains?(content_type, "image/jpg") -> ".jpg"
      String.contains?(content_type, "image/png") -> ".png"
      String.contains?(content_type, "image/gif") -> ".gif"
      String.contains?(content_type, "image/webp") -> ".webp"
      String.contains?(content_type, "image/avif") -> ".avif"
      true -> ".jpg"  # Default to jpg for unknown types
    end
  end

  # Download file from URL to specified path
  defp download_file(url, path) do
    try do
      case HTTPoison.get(url, [], follow_redirect: true, max_redirects: 5) do
        {:ok, %{status_code: 200, body: body}} ->
          File.write!(path, body)
          {:ok, path}

        {:ok, %{status_code: status}} ->
          Logger.error("Failed to download file from #{url}, status code: #{status}")
          {:error, "HTTP status #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTPoison error downloading file from #{url}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception downloading file from #{url}: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Downloads an event hero image from a URL.
  Convenience wrapper around download_image/2 with event-specific setup.
  Processes extensions and content types to ensure Waffle compatibility.

  ## Parameters
    - url: The URL of the hero image to download
    - force_refresh: When true, will download the image regardless of whether it exists already

  ## Returns
    - {:ok, %Plug.Upload{}} if successful, compatible with Waffle's cast_attachments
    - {:error, reason} if download fails
  """
  def download_event_hero_image(url, force_refresh \\ false)

  def download_event_hero_image(url, force_refresh) when is_binary(url) and url != "" do
    # CRITICAL FIX: Handle nil case for force_refresh - if nil, use false as the default
    # This avoids errors when using Process.get that might return nil
    force_refresh = if is_nil(force_refresh), do: false, else: force_refresh

    # Log force_refresh as is, without potentially overriding it
    # We need to be explicit about what force_refresh value we're using
    Logger.info("📸 Processing event hero image URL: #{url}, force_refresh: #{inspect(force_refresh)}")

    # Get the base filename from the URL and normalize it
    basename = url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
    |> normalize_filename()

    # Just use the original filename with no modification
    # Let download_image use it directly with the force_refresh value explicitly
    try do
      # Be explicit about passing the force_refresh parameter
      case download_image(url, basename, force_refresh) do
        %{filename: filename, path: path} when not is_nil(path) ->
          # Get file extension - needed for content type and proper file handling
          ext = Path.extname(filename) |> String.downcase()

          # Create a Plug.Upload struct compatible with Waffle's cast_attachments
          content_type = case ext do
            ".jpg" -> "image/jpeg"
            ".jpeg" -> "image/jpeg"
            ".png" -> "image/png"
            ".gif" -> "image/gif"
            ".webp" -> "image/webp"
            ".avif" -> "image/avif"
            _ -> "image/jpeg" # Default
          end

          # Ensure we're using a proper name that Waffle can process
          # Strip any path info to ensure we just have the filename
          clean_filename = Path.basename(filename)

          plug_upload = %Plug.Upload{
            path: path,
            filename: clean_filename,
            content_type: content_type
          }

          Logger.info("✅ Successfully processed event hero image from #{url}")
          {:ok, plug_upload}

        nil ->
          Logger.warning("⚠️ Failed to download event hero image from #{url}")
          {:error, :download_failed}
      end
    rescue
      e ->
        Logger.error("❌ Event hero image processing error for #{url}: #{Exception.message(e)}")
        {:error, :processing_error}
    end
  end

  def download_event_hero_image("", _force_refresh), do: {:error, :empty_url}
  def download_event_hero_image(nil, _force_refresh), do: {:error, :nil_url}
  def download_event_hero_image(_, _force_refresh), do: {:error, :invalid_url}

  @doc """
  Downloads a performer profile image from a URL.
  Convenience wrapper around download_image/2 with performer-specific prefix.

  ## Parameters
    - url: The URL of the performer image to download
    - force_refresh: When true, will download the image regardless of whether it exists already

  ## Returns
    - A Plug.Upload struct if successful, compatible with Waffle's cast_attachments
    - `nil` if the download fails
  """
  def download_performer_image(url, force_refresh \\ false) when is_binary(url) do
    # CRITICAL FIX: Handle nil case for force_refresh - if nil, use false as the default
    # This avoids errors when force_refresh is nil from Process.get
    force_refresh = if is_nil(force_refresh), do: false, else: force_refresh

    # Get the base filename from the URL and normalize it
    basename = url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
    |> normalize_filename()

    # Use the original filename without modification - just like hero images
    # Let download_image use it directly
    case download_image(url, basename, force_refresh) do
      %{filename: filename, path: path} when not is_nil(path) ->
        # Create a Plug.Upload struct compatible with Waffle's cast_attachments
        content_type = case Path.extname(filename) |> String.downcase() do
          ".jpg" -> "image/jpeg"
          ".jpeg" -> "image/jpeg"
          ".png" -> "image/png"
          ".gif" -> "image/gif"
          ".webp" -> "image/webp"
          ".avif" -> "image/avif"
          _ -> "image/jpeg" # Default
        end

        %Plug.Upload{
          path: path,
          filename: filename,
          content_type: content_type
        }
      nil -> nil
    end
  end

  @doc """
  Downloads a performer profile image from a URL with safety checks.
  Similar to download_performer_image/1 but with improved error handling.

  Advantages over download_performer_image:
  - Runs in a Task with timeout to prevent hanging
  - Returns {:ok, image} or {:error, reason} tuples consistently
  - Ensures filenames have proper extensions
  - Gracefully handles all error cases

  ## Parameters
    - url: The URL of the performer image to download
    - force_refresh: When true, will download the image regardless of whether it exists already

  ## Returns
    - {:ok, %Plug.Upload{}} if successful
    - {:ok, nil} if the download fails but processing should continue
    - {:error, reason} if the URL is invalid
  """
  def safe_download_performer_image(url, force_refresh \\ false) do
    # CRITICAL FIX: Handle nil case for force_refresh - if nil, use false as the default
    # This avoids errors when force_refresh is nil from Process.get
    force_refresh = if is_nil(force_refresh), do: false, else: force_refresh

    # Skip nil URLs early
    if is_nil(url) or (is_binary(url) and String.trim(url) == "") do
      {:error, "Invalid image URL"}
    else
      task = Task.async(fn ->
        case download_performer_image(url, force_refresh) do
          nil -> nil
          result ->
            # Ensure the filename has a proper extension
            extension = case Path.extname(url) do
              "" -> ".jpg"  # Default to jpg if no extension
              ext -> ext
            end

            # If result is a Plug.Upload struct, ensure it has the extension
            if is_map(result) && Map.has_key?(result, :filename) && !String.contains?(result.filename, ".") do
              Logger.debug("📸 Adding extension #{extension} to filename: #{result.filename}")
              %{result | filename: result.filename <> extension}
            else
              result
            end
        end
      end)

      # Increase timeout for image downloads
      case Task.yield(task, 40_000) || Task.shutdown(task) do
        {:ok, result} ->
          # Handle any result (including nil)
          {:ok, result}
        _ ->
          Logger.error("Timeout or error downloading performer image from #{url}")
          # Return nil instead of error to allow processing to continue
          {:ok, nil}
      end
    end
  end
end

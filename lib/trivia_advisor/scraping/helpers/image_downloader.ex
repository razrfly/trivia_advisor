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

  ## Returns
    - A file struct with `filename` and `path` keys if successful
    - `nil` if the download fails

  ## Example
      ImageDownloader.download_image("https://example.com/image.jpg", "performer")
      # => %{filename: "performer_123456.jpg", path: "/tmp/performer_123456.jpg"}
  """
  def download_image(url, prefix \\ "image") when is_binary(url) do
    Logger.debug("📥 Downloading image from URL: #{url}")

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

    # Use the prefix directly if it includes a hash pattern (our consistent filenames)
    # Otherwise generate a random filename as before
    filename = if String.contains?(prefix, "_") do
      "#{prefix}#{extension}"
    else
      hash = :crypto.strong_rand_bytes(16) |> Base.encode16()
      "#{prefix}_#{hash}#{extension}"
    end

    # Create full path for downloaded file
    path = Path.join(tmp_dir, filename)

    Logger.debug("📄 Will save image to: #{path}")

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
  Returns a result tuple with a Plug.Upload struct or error.

  ## Parameters
    - url: The URL of the hero image to download

  ## Returns
    - {:ok, %Plug.Upload{}} if successful
    - {:error, reason} if download fails
  """
  def download_event_hero_image(url) when is_binary(url) and url != "" do
    Logger.info("📸 Processing event hero image URL: #{url}")

    # Generate a deterministic filename based on the URL
    url_hash = :crypto.hash(:md5, url) |> Base.encode16()
    consistent_filename = "event_hero_#{url_hash}"

    try do
      case download_image(url, consistent_filename) do
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

  def download_event_hero_image(""), do: {:error, :empty_url}
  def download_event_hero_image(nil), do: {:error, :nil_url}
  def download_event_hero_image(_), do: {:error, :invalid_url}

  @doc """
  Downloads a performer profile image from a URL.
  Convenience wrapper around download_image/2 with performer-specific prefix.

  ## Parameters
    - url: The URL of the performer image to download

  ## Returns
    - A Plug.Upload struct if successful, compatible with Waffle's cast_attachments
    - `nil` if the download fails
  """
  def download_performer_image(url) when is_binary(url) do
    # Generate a deterministic filename based on the URL
    url_hash = :crypto.hash(:md5, url) |> Base.encode16()
    consistent_filename = "performer_image_#{url_hash}"

    case download_image(url, consistent_filename) do
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
end

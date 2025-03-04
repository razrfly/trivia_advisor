defmodule TriviaAdvisor.Scraping.Helpers.ImageDownloader do
  @moduledoc """
  Helper module for downloading images from URLs.
  Provides centralized functionality for image downloading across scrapers.

  Note: There are other image downloading functions in the codebase:
  - VenueHelpers.download_image - Used for venue-related images, returns {:ok, map} tuples
  - GooglePlaceImageStore.download_image - Specialized for Google Place images with specific headers

  This module exists to handle performer image downloading specifically, with a unified interface
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
  def download_image(url, prefix \\ "image") do
    try do
      # Extract file extension from URL
      file_extension = url |> Path.extname() |> String.downcase()

      # If no extension or unknown extension, try to detect from content-type
      file_extension = if file_extension in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"] do
        file_extension
      else
        Logger.debug("No file extension in URL, attempting to detect from content")
        detect_extension_from_url(url)
      end

      # Create a temporary file path
      temp_dir = System.tmp_dir!()
      random_id = :crypto.strong_rand_bytes(16) |> Base.encode16()
      temp_file = Path.join(temp_dir, "#{prefix}_#{random_id}#{file_extension}")

      Logger.debug("Downloading image from #{url} to #{temp_file}")

      # Download the image
      case HTTPoison.get(url, [], follow_redirect: true, max_redirects: 5) do
        {:ok, %{status_code: 200, body: body, headers: headers}} ->
          # Check content type if we couldn't determine extension from URL
          final_extension = if file_extension == ".jpg" do
            case get_content_type(headers) do
              nil -> file_extension
              content_type ->
                ext = extension_from_content_type(content_type)
                if ext != file_extension do
                  Logger.debug("Detected content type: #{content_type}, using extension: #{ext}")
                  ext
                else
                  file_extension
                end
            end
          else
            file_extension
          end

          # Update the file path if extension changed
          final_temp_file = if final_extension != file_extension do
            Path.rootname(temp_file) <> final_extension
          else
            temp_file
          end

          # Write the file
          File.write!(final_temp_file, body)

          Logger.debug("Successfully wrote image to: #{final_temp_file}")

          # Create a proper file struct for Waffle
          %{
            filename: Path.basename(final_temp_file),
            path: final_temp_file
          }

        {:ok, %{status_code: status}} ->
          Logger.error("Failed to download image from #{url} with status #{status}")
          nil

        {:error, error} ->
          Logger.error("Error downloading image from #{url}: #{inspect(error)}")
          nil
      end
    rescue
      e ->
        Logger.error("Error downloading image from #{url}: #{inspect(e)}")
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

  @doc """
  Downloads a performer profile image from a URL.
  Convenience wrapper around download_image/2 with performer-specific prefix.

  ## Parameters
    - url: The URL of the performer image to download

  ## Returns
    - A file struct with `file_name` and `updated_at` keys if successful, in the format
      Waffle expects for storage in the database
    - `nil` if the download fails
  """
  def download_performer_image(url) do
    case download_image(url, "performer_image") do
      %{filename: filename, path: path} = _downloaded ->
        # Create expected directory structure and copy files manually
        # This is what should be done by the API consumer, but we're making it easier

        # Here we're converting from the download format (filename/path)
        # to the storage format (file_name/updated_at) that Waffle expects
        # when storing the file metadata in the database
        %{
          file_name: filename,
          updated_at: NaiveDateTime.utc_now(),
          # Keep the path so it can be used to copy the file
          _temp_path: path
        }
      nil -> nil
    end
  end
end

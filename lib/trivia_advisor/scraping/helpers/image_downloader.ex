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

      # If no extension or unknown extension, default to jpg
      file_extension = if file_extension in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"] do
        file_extension
      else
        ".jpg"
      end

      # Create a temporary file path
      temp_dir = System.tmp_dir!()
      temp_file = Path.join(temp_dir, "#{prefix}_#{:rand.uniform(999999)}#{file_extension}")

      Logger.debug("Downloading image from #{url} to #{temp_file}")

      # Download the image
      case HTTPoison.get(url, [], follow_redirect: true, max_redirects: 5) do
        {:ok, %{status_code: 200, body: body}} ->
          # Write the file
          File.write!(temp_file, body)

          # Create a proper file struct for Waffle
          %{
            filename: Path.basename(temp_file),
            path: temp_file
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

  @doc """
  Downloads a performer profile image from a URL.
  Convenience wrapper around download_image/2 with performer-specific prefix.

  ## Parameters
    - url: The URL of the performer image to download

  ## Returns
    - A file struct with `filename` and `path` keys if successful
    - `nil` if the download fails
  """
  def download_performer_image(url) do
    download_image(url, "performer_image")
  end
end

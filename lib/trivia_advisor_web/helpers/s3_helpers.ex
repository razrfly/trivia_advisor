defmodule TriviaAdvisorWeb.Helpers.S3Helpers do
  @moduledoc """
  Helper module for handling S3 URL construction and encoding.
  This module centralizes S3 URL handling to ensure consistent URL structure
  and proper encoding across the application.
  """

  require Logger

  @doc """
  Constructs a full URL from a path, handling S3 storage and local development.
  Uses a simplified, direct approach to URL encoding.

  ## Examples

      iex> S3Helpers.construct_url("/path/to/file with spaces.jpg")
      "https://bucket-name.host.com/path/to/file%20with%20spaces.jpg"
  """
  def construct_url(path, default_img \\ nil) do
    if is_nil(path) or not is_binary(path) do
      Logger.debug("S3Helpers: nil or non-binary path, using default: #{inspect(default_img)}")
      default_img || default_image()
    else
      try do
        # Already a full URL?
        if String.starts_with?(path, "http") do
          Logger.debug("S3Helpers: Path already a URL: #{path}")
          path
        else
          # Use S3 or local storage based on config
          storage_type = Application.get_env(:waffle, :storage)
          Logger.debug("S3Helpers: Storage type: #{inspect(storage_type)}")

          if storage_type == Waffle.Storage.S3 do
            url = build_s3_url(path)
            Logger.debug("S3Helpers: Built S3 URL: #{url} from path: #{path}")
            url
          else
            url = build_local_url(path)
            Logger.debug("S3Helpers: Built local URL: #{url} from path: #{path}")
            url
          end
        end
      rescue
        e ->
          Logger.error("S3Helpers: Error constructing URL from path #{inspect(path)}: #{Exception.message(e)}")
          default_img || default_image()
      end
    end
  end

  @doc """
  Returns an HTML-safe URL that won't be re-encoded in templates.
  """
  def safe_url(path, default_img \\ nil) do
    Phoenix.HTML.raw(construct_url(path, default_img))
  end

  @doc """
  Constructs a hero image URL for a venue event.
  """
  def construct_hero_image_url(event, venue) do
    try do
      if is_nil(event) or is_nil(event.hero_image) or is_nil(event.hero_image.file_name) do
        nil
      else
        if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
          # Construct a simple path
          file_name = event.hero_image.file_name
          dir = "uploads/venues/#{venue.slug}"
          path = "#{dir}/original_#{file_name}"

          # Build the S3 URL
          build_s3_url(path)
        else
          # Use Waffle's local URL handling
          raw_url = TriviaAdvisor.Uploaders.HeroImage.url({event.hero_image, event})
          String.replace(raw_url, ~r{^/priv/static}, "")
        end
      end
    rescue
      e ->
        Logger.error("Error constructing hero image URL: #{Exception.message(e)}")
        nil
    end
  end

  @doc """
  Returns an HTML-safe hero image URL.
  """
  def safe_hero_image_url(event, venue) do
    Phoenix.HTML.raw(construct_hero_image_url(event, venue))
  end

  @doc """
  Returns a default placeholder image URL.
  """
  def default_image do
    "/images/default-placeholder.png"
  end

  # Private helpers

  defp build_s3_url(path) do
    # Get configuration
    bucket = System.get_env("BUCKET_NAME") || Application.get_env(:waffle, :bucket) || "trivia-app"
    s3_config = Application.get_env(:ex_aws, :s3, [])
    host = s3_config[:host] || "fly.storage.tigris.dev"

    Logger.debug("S3Helpers: Building S3 URL with bucket=#{bucket}, host=#{host}")

    # Clean the path (remove leading slash)
    clean_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path
    Logger.debug("S3Helpers: Clean path: #{clean_path}")

    # Simplified approach:
    # 1. First decode any potentially encoded content to avoid double-encoding
    decoded_path = URI.decode(clean_path)
    Logger.debug("S3Helpers: Decoded path: #{decoded_path}")

    # 2. For S3 URLs, we MANUALLY encode spaces as %20
    encoded_path = String.replace(decoded_path, " ", "%20")
    Logger.debug("S3Helpers: Encoded path: #{encoded_path}")

    # 3. Build the final URL
    url = "https://#{bucket}.#{host}/#{encoded_path}"
    Logger.debug("S3Helpers: Final URL: #{url}")
    url
  end

  defp build_local_url(path) do
    # Get endpoint configuration
    endpoint_url = TriviaAdvisorWeb.Endpoint.url()

    # Clean the path (remove leading slash)
    clean_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path

    # Simplified approach (same as S3)
    decoded_path = URI.decode(clean_path)
    encoded_path = String.replace(decoded_path, " ", "%20")

    # Build the final URL
    "#{endpoint_url}/#{encoded_path}"
  end
end

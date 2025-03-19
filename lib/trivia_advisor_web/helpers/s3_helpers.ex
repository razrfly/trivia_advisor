defmodule TriviaAdvisorWeb.Helpers.S3Helpers do
  @moduledoc """
  Helper module for handling S3 URL construction and encoding.
  This module centralizes S3 URL handling to ensure consistent URL structure
  and proper encoding across the application.
  """

  require Logger

  @doc """
  Constructs a full URL from a path, handling S3 storage and local development.
  Uses a direct encoding approach to avoid double-encoding issues with spaces.

  ## Examples

      iex> S3Helpers.construct_url("/path/to/file.jpg")
      "https://bucket-name.host.com/path/to/file.jpg"

      iex> S3Helpers.construct_url("http://existing-url.com/file.jpg")
      "http://existing-url.com/file.jpg"
  """
  def construct_url(path, default_img \\ nil) do
    # Return a default image if path is nil or not a binary
    if is_nil(path) or not is_binary(path) do
      default_img || default_image()
    else
      try do
        cond do
          # Already a full URL
          String.starts_with?(path, "http") ->
            path

          # Check if using S3 storage in production
          Application.get_env(:waffle, :storage) == Waffle.Storage.S3 ->
            # Format path correctly for S3 (remove leading slash if present)
            s3_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path
            bucket = System.get_env("TIGRIS_BUCKET_NAME") || System.get_env("BUCKET_NAME") || "trivia-app"

            # Get S3 configuration for host
            s3_config = Application.get_env(:ex_aws, :s3, [])
            host = case s3_config[:host] do
              h when is_binary(h) -> h
              _ -> "fly.storage.tigris.dev"
            end

            # Manually encode the path by splitting and encoding each segment
            # This prevents issues with double-encoding
            path_segments = String.split(s3_path, "/")
            encoded_segments = Enum.map(path_segments, fn segment ->
              # Replace spaces with %20 directly to avoid double encoding
              String.replace(segment, " ", "%20")
            end)

            encoded_path = "/" <> Enum.join(encoded_segments, "/")

            # Construct the URL with the manually encoded path
            "https://#{bucket}.#{host}#{encoded_path}"

          # Local development - use the app's URL config
          true ->
            endpoint_url = TriviaAdvisorWeb.Endpoint.url()
            if String.starts_with?(path, "/") do
              "#{endpoint_url}#{path}"
            else
              "#{endpoint_url}/#{path}"
            end
        end
      rescue
        e ->
          Logger.error("Error constructing URL from path #{inspect(path)}: #{Exception.message(e)}")
          default_img || default_image()
      end
    end
  end

  @doc """
  Constructs a hero image URL for a venue event with proper encoding.
  Uses a direct encoding approach to avoid double-encoding issues with spaces.
  """
  def construct_hero_image_url(event, venue) do
    try do
      if is_nil(event) or is_nil(event.hero_image) or is_nil(event.hero_image.file_name) do
        nil
      else
        if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
          # Get bucket name from env var, with fallback
          bucket = System.get_env("TIGRIS_BUCKET_NAME") ||
                   System.get_env("BUCKET_NAME") ||
                   "trivia-app"

          # Get S3 configuration
          s3_config = Application.get_env(:ex_aws, :s3, [])
          host = case s3_config[:host] do
            h when is_binary(h) -> h
            _ -> "fly.storage.tigris.dev"
          end

          # Construct the S3 path
          file_name = event.hero_image.file_name
          dir = "uploads/venues/#{venue.slug}"
          s3_path = "#{dir}/original_#{file_name}"

          # Manually encode the path by splitting and encoding each segment
          # This prevents issues with double-encoding
          path_segments = String.split(s3_path, "/")
          encoded_segments = Enum.map(path_segments, fn segment ->
            # Replace spaces with %20 directly to avoid double encoding
            String.replace(segment, " ", "%20")
          end)

          encoded_path = "/" <> Enum.join(encoded_segments, "/")

          # Construct the URL with the manually encoded path
          url = "https://#{bucket}.#{host}#{encoded_path}"
          Logger.debug("Constructed S3 URL for hero image: #{url}")
          url
        else
          # In development, use standard approach
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
  Returns a default placeholder image URL.
  """
  def default_image do
    "/images/default-placeholder.png"
  end
end

defmodule TriviaAdvisor.Helpers.ImageUrlHelper do
  @moduledoc """
  Helper functions for generating image URLs.
  Centralizes all URL generation logic for consistent CDN support.
  """

  require Logger

  @doc """
  Generates a URL for an image using Waffle's URL generation with CDN support.
  Will use the configured asset_host in production when available.

  ## Examples

      iex> ImageUrlHelper.get_image_url({file_name, venue}, TriviaAdvisor.Uploaders.HeroImage, :original)
      "http://cdn.quizadvisor.com/uploads/venues/venue-slug/original_image.jpg"

  """
  def get_image_url(file_tuple, uploader, version \\ :original) do
    try do
      uploader.url(file_tuple, version)
    rescue
      e ->
        Logger.error("Error generating URL via Waffle: #{Exception.message(e)}")
        fallback_url(file_tuple, uploader, version)
    end
  end

  @doc """
  Ensures a path is a full URL, handling both CDN and local development.
  Used for converting relative paths to full URLs.
  """
  def ensure_full_url(path) when is_binary(path) do
    cond do
      # Already a full URL
      String.starts_with?(path, "http") ->
        path

      # Check if using S3 storage in production
      Application.get_env(:waffle, :storage) == Waffle.Storage.S3 ->
        # Check for asset_host configuration
        asset_host = Application.get_env(:waffle, :asset_host)

        if is_binary(asset_host) do
          # Use CDN URL via asset_host
          s3_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path
          "#{asset_host}/#{s3_path}"
        else
          # Fall back to S3 URL if no asset_host
          # Get S3 configuration
          s3_config = Application.get_env(:ex_aws, :s3, [])
          bucket = Application.get_env(:waffle, :bucket, "trivia-advisor")

          host = case s3_config[:host] do
            h when is_binary(h) -> h
            _ -> "fly.storage.tigris.dev"
          end

          # Format path correctly for S3 (remove leading slash)
          s3_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path

          # Construct the full S3 URL
          "https://#{bucket}.#{host}/#{s3_path}"
        end

      # Local development
      true ->
        if String.starts_with?(path, "/") do
          "#{TriviaAdvisorWeb.Endpoint.url()}#{path}"
        else
          "#{TriviaAdvisorWeb.Endpoint.url()}/#{path}"
        end
    end
  rescue
    e ->
      Logger.error("Error constructing URL from path #{inspect(path)}: #{Exception.message(e)}")
      path
  end

  def ensure_full_url(nil), do: nil

  # Fallback URL generation when Waffle's built-in URL function fails
  defp fallback_url({file_name, scope}, uploader, version) when is_binary(file_name) do
    try do
      # Get the storage dir from the uploader if it supports it
      storage_dir = if function_exported?(uploader, :storage_dir, 2) do
        uploader.storage_dir(version, {file_name, scope})
      else
        ""
      end

      # Format the filename according to the uploader's convention if possible
      formatted_name = if function_exported?(uploader, :filename, 2) do
        _base_name = Path.basename(file_name, Path.extname(file_name))
        extension = Path.extname(file_name)
        "#{uploader.filename(version, {%{file_name: file_name}, scope})}#{extension}"
      else
        "#{version}_#{Path.basename(file_name)}"
      end

      # Combine path components
      path = Path.join([storage_dir, formatted_name])

      # Use ensure_full_url to handle CDN and other URL formatting
      ensure_full_url(path)
    rescue
      e ->
        Logger.error("Fallback URL generation failed: #{Exception.message(e)}")
        # Just return the raw filename as a last resort
        file_name
    end
  end

  defp fallback_url(_, _, _), do: nil
end

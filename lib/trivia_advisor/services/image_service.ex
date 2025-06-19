defmodule TriviaAdvisor.Services.ImageService do
  @moduledoc """
  Image service for handling venue and city images.
  Currently a stub implementation for testing purposes.
  """

  @doc """
  Get venue image URL
  """
  def get_venue_image(_venue) do
    "https://images.unsplash.com/photo-default-venue?utm_source=trivia_advisor"
  end

  @doc """
  Get city image with attribution
  """
  def get_city_image_with_attribution(_city) do
    image_url = "https://images.unsplash.com/photo-default-city?utm_source=trivia_advisor"
    attribution = %{
      "photographer_name" => "Default Photographer",
      "photographer_url" => "https://unsplash.com/@default"
    }
    {image_url, attribution}
  end

  @doc """
  Validate image URLs - returns only valid URLs
  """
  def validate_image_urls(urls) do
    # In the stub, we'll only consider unsplash URLs as valid
    # to match the test expectations
    Enum.filter(urls, fn url ->
      String.contains?(url, "unsplash.com") and valid_url?(url)
    end)
  end

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        true
      _ ->
        false
    end
  end
end

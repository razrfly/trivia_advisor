defmodule TriviaAdvisorWeb.Helpers.ImageHelpers do
  @moduledoc """
  Helper functions for handling images across views.
  """
  alias TriviaAdvisor.Helpers.ImageUrlHelper
  alias TriviaAdvisor.Services.ImageCache
  require Logger

  @doc """
  Gets a suitable image URL for a venue.
  First checks for direct venue image sources, then falls back to API via cache.
  """
  def get_venue_image(venue) do
    try do
      # First check for events with hero_image
      event_image =
        try do
          if venue.events && Enum.any?(venue.events) do
            event = List.first(venue.events)

            if event && event.hero_image && event.hero_image.file_name do
              try do
                # Use helper to generate URL
                ImageUrlHelper.get_image_url({event.hero_image.file_name, event}, TriviaAdvisor.Uploaders.HeroImage, :original)
              rescue
                e ->
                  Logger.error("Error processing hero image URL: #{Exception.message(e)}")
                  nil
              end
            else
              nil
            end
          end
        rescue
          _ -> nil
        end

      # Check for stored Google Place images
      google_place_image = if is_map(venue) && Map.get(venue, :google_place_images) && is_list(venue.google_place_images) && Enum.any?(venue.google_place_images) do
        try do
          # Get the first image from stored place images
          first_image = List.first(venue.google_place_images)
          if is_map(first_image) && Map.has_key?(first_image, "local_path") && is_binary(first_image["local_path"]) do
            ImageUrlHelper.ensure_full_url(first_image["local_path"])
          else
            nil
          end
        rescue
          _ -> nil
        end
      end

      # Check for hero_image_url in metadata
      metadata_image = if is_map(venue) && Map.has_key?(venue, :metadata) && is_map(venue.metadata) do
        venue.metadata["hero_image_url"] ||
        venue.metadata["hero_image"] ||
        venue.metadata["image_url"] ||
        venue.metadata["image"]
      end

      # Check if venue has a field for hero_image directly
      venue_image = if is_map(venue) do
        Map.get(venue, :hero_image_url) ||
        Map.get(venue, :hero_image) ||
        Map.get(venue, :image_url) ||
        Map.get(venue, :image)
      end

      # Use the first available image or fall back to the ImageCache/API
      image_url = event_image || google_place_image || metadata_image || venue_image

      if is_binary(image_url) do
        # Use helper to ensure it's a full URL
        ImageUrlHelper.ensure_full_url(image_url)
      else
        # Fall back to the Unsplash API via cache
        ImageCache.get_venue_image(venue)
      end
    rescue
      e ->
        Logger.error("Error getting venue image: #{inspect(e)}")
        # Fallback to default
        "/images/default-venue.jpg"
    end
  end

  @doc """
  Gets a city image URL with attribution.
  Uses data from city records or Unsplash API via cache.
  """
  def get_city_image_with_attribution(city) do
    try do
      # Use the ImageCache to handle city images (from DB or API)
      ImageCache.get_city_image_with_attribution(city)
    rescue
      e ->
        Logger.error("Error getting city image: #{inspect(e)}")
        # Fallback default image
        default_image_url = "/images/default_city.jpg"
        {default_image_url, %{"photographer_name" => "Default Image"}}
    end
  end

  # Function to ensure UTM parameters are added to attribution URLs
  def ensure_utm_parameters(attribution) do
    utm_params = "?utm_source=trivia_advisor&utm_medium=referral"

    # Handle both string and atom keys
    photographer_url = Map.get(attribution, "photographer_url") || Map.get(attribution, :photographer_url)
    unsplash_url = Map.get(attribution, "unsplash_url") || Map.get(attribution, :unsplash_url)

    # Only update URLs if they exist and don't already have UTM params
    updated_attribution = attribution

    updated_attribution = if photographer_url && not String.contains?(photographer_url, "utm_source") do
      Map.put(updated_attribution, "photographer_url", "#{photographer_url}#{utm_params}")
    else
      updated_attribution
    end

    updated_attribution = if unsplash_url && not String.contains?(unsplash_url, "utm_source") do
      Map.put(updated_attribution, "unsplash_url", "#{unsplash_url}#{utm_params}")
    else
      updated_attribution
    end

    updated_attribution
  end
end

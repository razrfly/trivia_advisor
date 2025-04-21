defmodule TriviaAdvisorWeb.Helpers.ImageHelpers do
  @moduledoc """
  Helper functions for handling images across views.
  """
  alias TriviaAdvisor.Helpers.ImageUrlHelper
  require Logger

  @doc """
  Gets a suitable image URL for a venue.
  Tries several potential sources in order of preference.
  """
  def get_venue_image(venue) do
    try do
      # Check for events with hero_image
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

      # Use the first available image or fall back to placeholder
      image_url = event_image || google_place_image || metadata_image || venue_image

      if is_binary(image_url) do
        # Use helper to ensure it's a full URL
        ImageUrlHelper.ensure_full_url(image_url)
      else
        "/images/default-venue.jpg"
      end
    rescue
      e ->
        Logger.error("Error getting venue image: #{inspect(e)}")
        "/images/default-venue.jpg"
    end
  end

  @doc """
  Gets a city image URL from Unsplash or fallbacks.
  Returns a tuple with {image_url, attribution_map}.
  """
  def get_city_image_with_attribution(city) do
    # Default image URL if none is found
    default_image_url = "/images/default_city.jpg"

    if city.unsplash_gallery &&
       is_map(city.unsplash_gallery) &&
       Map.has_key?(city.unsplash_gallery, "images") &&
       is_list(city.unsplash_gallery["images"]) &&
       length(city.unsplash_gallery["images"]) > 0 do

      # Get the current index or default to 0
      current_index = Map.get(city.unsplash_gallery, "current_index", 0)

      # Get the current image safely
      current_image = Enum.at(city.unsplash_gallery["images"], current_index) ||
                      List.first(city.unsplash_gallery["images"])

      if current_image && Map.has_key?(current_image, "url") do
        # Extract the image URL
        image_url = current_image["url"]

        # Extract attribution
        attribution = if Map.has_key?(current_image, "attribution") do
          # Ensure UTM parameters for photographer URL
          attribution = current_image["attribution"]
          ensure_utm_parameters(attribution)
        else
          %{"photographer_name" => "Photographer", "unsplash_url" => "https://unsplash.com?utm_source=trivia_advisor&utm_medium=referral"}
        end

        {image_url, attribution}
      else
        # Fallback to default if no URL in the gallery
        {default_image_url, %{"photographer_name" => "Default Image"}}
      end
    else
      # If no gallery or no images, use fallback hardcoded image URL
      image_url = get_fallback_city_image(city.name)
      {image_url, %{"photographer_name" => "Unsplash", "unsplash_url" => "https://unsplash.com?utm_source=trivia_advisor&utm_medium=referral"}}
    end
  end

  # Ensure UTM parameters are present for attribution URLs
  defp ensure_utm_parameters(attribution) do
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

  @doc """
  Gets a fallback city image based on common city names.
  """
  def get_fallback_city_image(name) when is_binary(name) do
    cond do
      String.contains?(String.downcase(name), "london") ->
        "https://images.unsplash.com/photo-1533929736458-ca588d08c8be?q=80&w=2000"
      String.contains?(String.downcase(name), "new york") ->
        "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?q=80&w=2000"
      String.contains?(String.downcase(name), "sydney") ->
        "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?q=80&w=2000"
      String.contains?(String.downcase(name), "melbourne") ->
        "https://images.unsplash.com/photo-1545044846-351ba102b6d5?q=80&w=2000"
      String.contains?(String.downcase(name), "paris") ->
        "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?q=80&w=2000"
      String.contains?(String.downcase(name), "tokyo") ->
        "https://images.unsplash.com/photo-1503899036084-c55cdd92da26?q=80&w=2000"
      true ->
        "https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?q=80&w=2000" # Default urban image
    end
  end
  def get_fallback_city_image(_), do: "https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?q=80&w=2000"
end

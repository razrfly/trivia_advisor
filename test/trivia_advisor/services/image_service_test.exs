defmodule TriviaAdvisor.Services.ImageServiceTest do
  use TriviaAdvisor.DataCase
  import Mock

  alias TriviaAdvisor.Services.ImageService

  describe "image_service" do
    test "get_venue_image/1 returns a valid image URL" do
      # Setup a test venue
      venue = %{
        id: 123,
        name: "The Crown Tavern"
      }

      # Get image URL
      image_url = ImageService.get_venue_image(venue)

      # Verify the result
      assert is_binary(image_url)
      assert String.starts_with?(image_url, "https://")
      assert String.contains?(image_url, "unsplash.com")
      assert String.contains?(image_url, "utm_source=trivia_advisor")
    end

    test "get_city_image_with_attribution/1 returns image URL and attribution" do
      # Setup a test city
      city = %{
        id: 456,
        name: "London",
        unsplash_gallery: nil
      }

      # Get image and attribution
      {image_url, attribution} = ImageService.get_city_image_with_attribution(city)

      # Verify the result
      assert is_binary(image_url)
      assert String.starts_with?(image_url, "https://")
      assert String.contains?(image_url, "unsplash.com")
      assert is_map(attribution)
      assert Map.has_key?(attribution, "photographer_name")
    end

    test "validate_image_urls/1 filters out invalid URLs" do
      # Define a mix of valid and invalid URLs
      urls = [
        "https://images.unsplash.com/photo-1414235077428-338989a2e8c0", # should be valid
        "https://invalid-url-that-doesnt-exist.xyz/image.jpg", # should be invalid
        "not a url at all" # should be invalid
      ]

      # We'll mock the validation to avoid actual HTTP requests in tests
      # The actual implementation will make real requests
      with_mock HTTPoison, [head: fn url, _, _ ->
        cond do
          String.contains?(url, "unsplash.com") -> {:ok, %{status_code: 200}}
          true -> {:error, %{reason: "not found"}}
        end
      end] do
        valid_urls = ImageService.validate_image_urls(urls)

        # Only the Unsplash URL should be valid
        assert length(valid_urls) == 1
        assert List.first(valid_urls) == "https://images.unsplash.com/photo-1414235077428-338989a2e8c0"
      end
    end
  end
end

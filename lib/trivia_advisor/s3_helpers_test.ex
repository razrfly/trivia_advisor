defmodule TriviaAdvisor.S3HelpersTest do
  @moduledoc """
  Simple test module to verify S3Helpers URL encoding.

  Run with: mix run -e "TriviaAdvisor.S3HelpersTest.run()"
  """

  alias TriviaAdvisorWeb.Helpers.S3Helpers
  require Logger

  def run do
    Application.put_env(:waffle, :storage, Waffle.Storage.S3)
    IO.puts("===== Testing S3Helpers URL encoding =====")

    # Test with filenames that have spaces
    test_paths = [
      "/uploads/venues/test-venue/original_test file with spaces.jpg",
      "/uploads/venues/test-venue/original_65c9aab7296d16fa251695a5_nsw - hotel downing.png",
      "/uploads/venues/test-venue/original_file-with-dashes.jpg"
    ]

    for path <- test_paths do
      IO.puts("\nTesting S3Helpers.construct_url with: #{path}")

      # Generate URL using our helper
      url = S3Helpers.construct_url(path)
      IO.puts("Generated URL: #{url}")

      # Parse the URL to check that spaces are properly encoded
      uri = URI.parse(url)
      IO.puts("Path component: #{uri.path}")
      IO.puts("Spaces properly encoded? #{!String.contains?(uri.path, " ")}")
    end

    # Test hero image URL construction
    test_hero_image_url()

    IO.puts("\n===== Test complete =====")
  end

  def test_hero_image_url do
    IO.puts("\n--- Testing hero image URL construction ---")

    # Mock venue and event with hero image
    venue = %{
      slug: "test-venue",
      name: "Test Venue"
    }

    event = %{
      id: 123,
      venue: venue,
      hero_image: %{
        file_name: "test file with spaces.jpg"
      }
    }

    # Generate URL using our helper
    url = S3Helpers.construct_hero_image_url(event, venue)
    IO.puts("Generated hero image URL: #{url}")

    # Parse the URL to check that spaces are properly encoded
    uri = URI.parse(url)
    IO.puts("Path component: #{uri.path}")
    IO.puts("Spaces properly encoded? #{!String.contains?(uri.path, " ")}")
  end
end

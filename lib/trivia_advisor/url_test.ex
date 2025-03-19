defmodule TriviaAdvisor.URLTest do
  @moduledoc """
  Module for testing S3 URL generation and encoding.
  This is a utility for development and testing, not for production use.

  Run with:
  mix run -e "TriviaAdvisor.URLTest.run()"
  """

  require Logger

  def run do
    IO.puts("==== S3 URL Generation Test ====")
    IO.puts("Testing with environment variables:")

    # Load environment variables from .env file if present
    load_dotenv()

    # Print out environment variables related to S3
    IO.puts("BUCKET_NAME: #{System.get_env("BUCKET_NAME") || "(not set)"}")
    IO.puts("TIGRIS_BUCKET_NAME: #{System.get_env("TIGRIS_BUCKET_NAME") || "(not set)"}")
    IO.puts("AWS_REGION: #{System.get_env("AWS_REGION") || "(not set)"}")
    IO.puts("AWS_ACCESS_KEY_ID: #{System.get_env("AWS_ACCESS_KEY_ID") || "(not set, length hidden)" |> String.slice(0..5)}...}")
    IO.puts("AWS_SECRET_ACCESS_KEY: #{if System.get_env("AWS_SECRET_ACCESS_KEY"), do: "Set (hidden)", else: "(not set)"}")

    # Test various file paths with Waffle's built-in URL generation
    test_waffle_url()

    # Test file paths manually with different URL encoding strategies
    test_s3_urls_with_encodings()

    # Test S3Helpers URL encoding
    test_s3_helpers_url()
  end

  def test_waffle_url do
    IO.puts("\n=== Testing Waffle's built-in URL generation ===")

    # Test if Waffle properly handles URL encoding
    # First, set up the Waffle configuration to use S3
    Application.put_env(:waffle, :storage, Waffle.Storage.S3)

    # Print the current storage setting
    IO.puts("Waffle storage setting: #{inspect(Application.get_env(:waffle, :storage))}")

    # Create a mock file and upload structure like Waffle would use
    mock_file = %{file_name: "test file with spaces.jpg"}
    mock_event = %{id: 123, hero_image: mock_file}
    _mock_venue = %{slug: "test-venue"}

    # Try to generate the URL using Waffle (if applicable)
    try do
      IO.puts("Trying to generate URL with TriviaAdvisor.Uploaders.HeroImage...")
      url = TriviaAdvisor.Uploaders.HeroImage.url({mock_file, mock_event})
      IO.puts("Generated URL: #{url}")
    rescue
      e -> IO.puts("Error generating URL with Waffle: #{Exception.message(e)}")
    end
  end

  def test_s3_urls_with_encodings do
    IO.puts("\n=== Testing manual S3 URL generation with different encodings ===")

    # Test file path with spaces
    path = "uploads/venues/test-venue/original_test file with spaces.jpg"
    bucket = System.get_env("TIGRIS_BUCKET_NAME") || System.get_env("BUCKET_NAME") || "trivia-app"
    host = "fly.storage.tigris.dev"

    # Test 1: Standard URL joining (filename unchanged)
    IO.puts("\n1. Standard URL joining (raw filename)")
    url = "https://#{bucket}.#{host}/#{path}"
    IO.puts("URL: #{url}")

    # Test 2: Using URI module
    IO.puts("\n2. Using URI module to encode")
    path_encoded = URI.encode_www_form(path)
    url = "https://#{bucket}.#{host}/#{path_encoded}"
    IO.puts("URL with URI.encode_www_form: #{url}")

    # Test 3: URI encode/encode component
    IO.puts("\n3. Using different URI encode methods")
    IO.puts("With URI.encode: #{URI.encode(path)}")
    IO.puts("With URI.encode_www_form: #{URI.encode_www_form(path)}")

    # Test 4: Check if TriviaAdvisorWeb.Helpers.S3Helpers exists and use it if available
    IO.puts("\n4. Using helper modules if available")

    alias TriviaAdvisorWeb.Helpers.S3Helpers

    real_path = "uploads/venues/hotel-downing/original_65c9aab7296d16fa251695a5_nsw - hotel downing.png"

    try do
      url = S3Helpers.construct_url(real_path)
      IO.puts("URL from S3Helpers: #{url}")
    rescue
      _ ->
        # Try using the built-in helper from venue/show.ex
        try do
          IO.puts("Attempting to use helper from venue/show.ex...")
          url = S3Helpers.construct_url(real_path)
          IO.puts("URL from construct_url: #{url}")
        rescue
          e -> IO.puts("No suitable helper available: #{Exception.message(e)}")
        end
    end

    # Test 3: URI encode methods
    IO.puts("\n3. Using different URI encode methods")
    IO.puts("With URI.encode: #{URI.encode(path)}")
    IO.puts("With URI.encode_www_form: #{URI.encode_www_form(path)}")

    # Test with the specific problem URL from the user
    IO.puts("\n5. Testing with the problematic URL")
    problem_path = "uploads/venues/hotel-downing/original_65c9aab7296d16fa251695a5_nsw - hotel downing.png"

    IO.puts("Raw URL: https://#{bucket}.#{host}/#{problem_path}")

    # Try different encoding approaches
    encoded_url = "https://#{bucket}.#{host}/#{URI.encode(problem_path)}"
    IO.puts("URI.encode: #{encoded_url}")

    # Test encoding only the filename part
    dir = Path.dirname(problem_path)
    filename = Path.basename(problem_path)
    encoded_filename = URI.encode(filename)
    partially_encoded = "#{dir}/#{encoded_filename}"
    IO.puts("Encoding only filename: https://#{bucket}.#{host}/#{partially_encoded}")

    # Test with path segment encoding
    path_parts = String.split(problem_path, "/")
    encoded_parts = Enum.map(path_parts, &URI.encode/1)
    path_with_encoded_parts = Enum.join(encoded_parts, "/")
    IO.puts("Path segment encoding: https://#{bucket}.#{host}/#{path_with_encoded_parts}")

    IO.puts("\n==== Tests Complete ====")
  end

  def test_s3_helpers_url do
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
      url = TriviaAdvisorWeb.Helpers.S3Helpers.construct_url(path)
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
    url = TriviaAdvisorWeb.Helpers.S3Helpers.construct_hero_image_url(event, venue)
    IO.puts("Generated hero image URL: #{url}")

    # Parse the URL to check that spaces are properly encoded
    uri = URI.parse(url)
    IO.puts("Path component: #{uri.path}")
    IO.puts("Spaces properly encoded? #{!String.contains?(uri.path, " ")}")
  end

  # Helper to load environment variables from .env file
  defp load_dotenv do
    try do
      {result, _} = System.cmd("test", ["-f", ".env"])

      if result == "" do
        env_contents = File.read!(".env")

        env_contents
        |> String.split("\n")
        |> Enum.each(fn line ->
          if String.trim(line) != "" && !String.starts_with?(line, "#") do
            [key, value] = String.split(line, "=", parts: 2)
            System.put_env(String.trim(key), String.trim(value))
          end
        end)

        IO.puts("Loaded environment variables from .env file")
      end
    rescue
      e -> IO.puts("Failed to load .env file: #{Exception.message(e)}")
    end
  end
end

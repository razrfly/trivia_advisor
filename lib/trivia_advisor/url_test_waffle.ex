defmodule TriviaAdvisor.URLTestWaffle do
  @moduledoc """
  Test module to test URL generation with Waffle and URI encoding.

  Run with: mix run -e "TriviaAdvisor.URLTestWaffle.run()"
  """

  require Logger

  def run do
    IO.puts("===== Testing URL Generation with URI structs =====")

    # Setup test environment
    Application.put_env(:waffle, :storage, Waffle.Storage.S3)

    # Test with various filenames, especially those with spaces
    test_filenames = [
      # This is the problematic example from the error
      "65c9aab7296d16fa251695a5_nsw - hotel downing.png",
      # Other test cases with spaces and special chars
      "test file with spaces.jpg",
      "file-with-dashes.jpg",
      "file_with_underscores.jpg",
      "file with spaces and dashes - test.jpg",
      "img_1335-768x800.webp",  # This is the working example URL
      "test+plus+sign.jpg",     # Test plus signs
      "test?query=params.jpg",  # Test query params
      "test&amp;special.jpg"    # Test HTML entities
    ]

    # Test each filename
    test_filenames |> Enum.each(&test_filename/1)

    # Test with venue and event structure
    test_with_venue_structure()

    # Test our implementation using S3Helpers
    test_s3_helpers()

    IO.puts("===== Tests Complete =====")
  end

  def test_filename(filename) do
    IO.puts("\n--- Testing with filename: #{filename} ---")

    # Create mock file and structures
    mock_file = %{file_name: filename}
    mock_event = %{id: 123, hero_image: mock_file, venue: %{slug: "test-venue"}}

    # Test URLs directly with Waffle
    test_waffle_url(filename, mock_file, mock_event)

    # Test different URL encoding approaches
    test_encoding_approaches(filename, "test-venue")
  end

  def test_waffle_url(_unused_filename, mock_file, mock_event) do
    IO.puts("\n1. Direct Waffle.Storage.S3 URL generation")
    try do
      # Direct Waffle approach (might fail with certain filenames)
      uploader_url = TriviaAdvisor.Uploaders.HeroImage.url({mock_file, mock_event})
      IO.puts("TriviaAdvisor.Uploaders.HeroImage.url result: #{uploader_url}")

      # Analyze URL components
      uri = URI.parse(uploader_url)
      IO.puts("URI parsed components:")
      IO.puts("  Scheme: #{uri.scheme}")
      IO.puts("  Host: #{uri.host}")
      IO.puts("  Path: #{uri.path}")
    rescue
      e -> IO.puts("Error with Waffle URL generation: #{Exception.message(e)}")
    end
  end

  def test_encoding_approaches(filename, venue_slug) do
    IO.puts("\n2. Testing URL encoding approaches")

    # Construct a path like we do in our app
    s3_path = Path.join(["uploads/venues", venue_slug, "original_#{filename}"])
    bucket = System.get_env("TIGRIS_BUCKET_NAME") || "trivia-app"
    host = "fly.storage.tigris.dev"

    # Method 1: Basic joining with no encoding
    raw_url = "https://#{bucket}.#{host}/#{s3_path}"
    IO.puts("Raw URL (no encoding): #{raw_url}")

    # Method 2: URI.encode - this causes double encoding in templates
    encoded_path = URI.encode(s3_path)
    encoded_url = "https://#{bucket}.#{host}/#{encoded_path}"
    IO.puts("URI.encode (can cause double-encoding): #{encoded_url}")

    # Method 3: URI struct approach - our new solution
    uri = URI.new!("https://#{bucket}.#{host}")
    |> URI.append_path("/#{s3_path}")
    uri_url = URI.to_string(uri)
    IO.puts("URI struct approach (prevents double-encoding): #{uri_url}")

    # Method 4: Use ExAws.Request.Url.sanitize like Waffle does
    sanitized_path = ExAws.Request.Url.sanitize(s3_path, :s3)
    sanitized_url = "https://#{bucket}.#{host}#{sanitized_path}"
    IO.puts("ExAws.Request.Url.sanitize: #{sanitized_url}")

    # Compare the URLs for equivalence
    IO.puts("\nURIs equal? #{uri_url == sanitized_url}")

    if uri_url != sanitized_url do
      # Compare paths for debugging
      uri_path = URI.parse(uri_url).path
      sanitized_parsed_path = URI.parse(sanitized_url).path
      IO.puts("URI path: #{uri_path}")
      IO.puts("Sanitized path: #{sanitized_parsed_path}")
    end
  end

  def test_with_venue_structure do
    IO.puts("\n--- Testing with real venue structure ---")

    # Create mock structure that matches our app's real structure
    venue = %{
      slug: "hotel-downing",
      name: "Hotel Downing",
      id: 999
    }

    event = %{
      id: 888,
      venue: venue,
      venue_id: venue.id,
      hero_image: %{
        file_name: "65c9aab7296d16fa251695a5_nsw - hotel downing.png",
        updated_at: ~N[2024-04-01 00:00:00]
      }
    }

    # Test our custom URL construction
    IO.puts("\nTesting our app's URL construction:")
    url = construct_hero_image_url(event, venue)
    IO.puts("Our app's construction (legacy): #{url}")

    # Test with URI struct approach
    url_with_uri = construct_hero_image_url_with_uri(event, venue)
    IO.puts("URI struct approach: #{url_with_uri}")

    # Try Waffle URL generation
    try do
      uploader_url = TriviaAdvisor.Uploaders.HeroImage.url({event.hero_image, event})
      IO.puts("HeroImage.url result: #{uploader_url}")
    rescue
      e -> IO.puts("Error with Waffle URL generation: #{Exception.message(e)}")
    end
  end

  def test_s3_helpers do
    IO.puts("\n--- Testing TriviaAdvisorWeb.Helpers.S3Helpers (simulated) ---")

    # We'll simulate the S3Helpers without importing the actual module

    bucket = System.get_env("TIGRIS_BUCKET_NAME") || "trivia-app"
    host = "fly.storage.tigris.dev"
    filename = "65c9aab7296d16fa251695a5_nsw - hotel downing.png"

    # Test typical paths that would be used in the app
    test_paths = [
      # Image path with spaces
      "/uploads/venues/test-venue/original_#{filename}",
      # Query string test
      "/uploads/venues/test-venue/original_test?with=params.jpg",
      # Path with plus signs
      "/uploads/venues/test-venue/original_test+plus+sign.jpg"
    ]

    Enum.each(test_paths, fn test_path ->
      IO.puts("\nTesting path: #{test_path}")

      # Simulate S3Helpers.construct_url
      s3_path = if String.starts_with?(test_path, "/"), do: String.slice(test_path, 1..-1//1), else: test_path

      # Use ExAws.Request.Url.sanitize like our updated S3Helpers module
      sanitized_path = ExAws.Request.Url.sanitize("/#{s3_path}", :s3)
      s3_url = "https://#{bucket}.#{host}#{sanitized_path}"

      IO.puts("S3Helpers URL (simulated with ExAws.Request.Url.sanitize): #{s3_url}")

      # Test if this URL would be double-encoded when sent to a template
      # In a real scenario, the HTML template system can cause additional encoding
      parsed_uri = URI.parse(s3_url)
      html_path = parsed_uri.path  # Already properly encoded

      IO.puts("Path as it would appear in HTML: #{html_path}")
      IO.puts("HTML path still valid? #{String.contains?(html_path, " ") == false}")
    end)
  end

  # Legacy version - similar to what we had before
  defp construct_hero_image_url(event, venue) do
    try do
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

        # Construct the base path
        file_name = event.hero_image.file_name
        dir = "uploads/venues/#{venue.slug}"
        base_filename = "original_#{file_name}"

        # Encode just the filename part, not the directory path
        encoded_filename = URI.encode(base_filename)

        # Construct the URL using proper encoding for just the filename
        "https://#{bucket}.#{host}/#{dir}/#{encoded_filename}"
      else
        # In development, use standard approach
        raw_url = TriviaAdvisor.Uploaders.HeroImage.url({event.hero_image, event})
        String.replace(raw_url, ~r{^/priv/static}, "")
      end
    rescue
      e ->
        Logger.error("Error constructing hero image URL: #{Exception.message(e)}")
        nil
    end
  end

  # New version with URI struct
  defp construct_hero_image_url_with_uri(event, venue) do
    try do
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

        # Use a URI struct to ensure proper encoding
        uri = URI.new!("https://#{bucket}.#{host}")
        |> URI.append_path("/#{s3_path}")

        URI.to_string(uri)
      else
        # In development, use standard approach
        raw_url = TriviaAdvisor.Uploaders.HeroImage.url({event.hero_image, event})
        String.replace(raw_url, ~r{^/priv/static}, "")
      end
    rescue
      e ->
        Logger.error("Error constructing hero image URL: #{Exception.message(e)}")
        nil
    end
  end
end

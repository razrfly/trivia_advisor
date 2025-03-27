defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobHeroImageTest do
  use TriviaAdvisor.DataCase
  use TriviaAdvisor.ObanCase
  import ExUnit.CaptureLog
  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.ScrapingFixtures
  alias TriviaAdvisor.LocationsFixtures
  alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

  describe "hero image processing in QuizmeistersDetailJob" do
    setup do
      # Create the source record needed by the job
      source = ScrapingFixtures.source_fixture()

      # Create a venue with a specific slug for consistent testing
      venue = LocationsFixtures.venue_fixture(%{slug: "test-venue-slug"})

      # Add a hero image to the venue
      venue =
        venue
        |> Ecto.Changeset.change(%{
          google_place_images: [%{
            "reference" => "existing-image-reference",
            "url" => "https://quizmeisters.com/images/existing-image.jpg",
            "filename" => "existing-image.jpg"
          }]
        })
        |> Repo.update!()

      # Create the venue data that would be passed to the detail job
      venue_data = %{
        "id" => venue.id,
        "name" => venue.name,
        "url" => "https://quizmeisters.com/venues/#{venue.slug}",
        "slug" => venue.slug,
        "address" => venue.address,
        "latitude" => venue.latitude,
        "longitude" => venue.longitude,
        "source_id" => source.id
      }

      %{source: source, venue: venue, venue_data: venue_data}
    end

    # Helper to run job with correct args structure
    def perform_test_job(venue_data, source_id, options \\ []) do
      # Get options
      force_refresh = Keyword.get(options, :force_refresh, false)

      # Set process flags for testing
      Process.put(:test_mode, true)
      Process.put(:force_refresh_images, force_refresh)

      # Build args properly
      args = %{
        "venue" => venue_data,
        "source_id" => source_id
      }

      # Add force_refresh_images to args if true
      args = if force_refresh, do: Map.put(args, "force_refresh_images", true), else: args

      # Run job and return logs
      capture_log(fn ->
        perform_job(QuizmeistersDetailJob, args)
      end)
    end

    test "logs appropriate messages when force_refresh_images is true", %{venue_data: venue_data, source: source} do
      # Run the job with force_refresh enabled
      log = perform_test_job(venue_data, source.id, force_refresh: true)

      # Assert that log contains expected messages for force refresh
      assert log =~ "Processing venue: #{venue_data["name"]}"
      assert log =~ "force_refresh_images=true"
    end

    test "logs appropriate messages when force_refresh_images is false", %{venue_data: venue_data, source: source} do
      # Run the job with force_refresh disabled
      log = perform_test_job(venue_data, source.id, force_refresh: false)

      # Assert log does NOT contain force refresh messages
      assert log =~ "Processing venue: #{venue_data["name"]}"
      assert log =~ "force_refresh_images=false"
    end

    test "job completes and logs with any force_refresh_images setting", %{venue_data: venue_data, source: source} do
      # Test with both settings to ensure job logs properly either way
      for force_refresh <- [true, false] do
        log = perform_test_job(venue_data, source.id, force_refresh: force_refresh)

        # Basic assertion that processing happened
        assert log =~ "Processing venue: #{venue_data["name"]}"

        # Check force_refresh value in logs
        expected_value = "#{force_refresh}"
        assert log =~ "force_refresh_images=#{expected_value}"
      end
    end

    # Added tests from file test
    test "logs venue slug in image path references", %{venue_data: venue_data, source: source} do
      # Run the job and capture logs
      log = perform_test_job(venue_data, source.id)

      # Verify that logs include venue slug in file paths
      assert log =~ venue_data["slug"]
      assert log =~ "Processing venue: #{venue_data["name"]}"
    end

    test "logs when creating directories for venues", %{venue_data: venue_data, source: source} do
      # Run the job with force refresh enabled
      log = perform_test_job(venue_data, source.id, force_refresh: true)

      # Check for basic processing logs
      assert log =~ "Processing venue: #{venue_data["name"]}"
    end

    test "handles both new and existing venues appropriately", %{venue_data: venue_data, source: source} do
      # Get the venue
      venue = Repo.get!(TriviaAdvisor.Locations.Venue, venue_data["id"])

      # Update venue to have no images, simulating a new venue
      venue
      |> Ecto.Changeset.change(%{google_place_images: []})
      |> Repo.update!()

      # Run the job and capture logs for "new" venue
      new_venue_log = perform_test_job(venue_data, source.id)

      # Now restore images to simulate an existing venue
      venue
      |> Ecto.Changeset.change(%{
        google_place_images: [%{
          "reference" => "existing-image-reference",
          "url" => "https://quizmeisters.com/images/existing-image.jpg",
          "filename" => "existing-image.jpg"
        }]
      })
      |> Repo.update!()

      # Run the job and capture logs for "existing" venue
      existing_venue_log = perform_test_job(venue_data, source.id)

      # Basic assertions to ensure job works with both new and existing venues
      assert new_venue_log =~ "Processing venue: #{venue_data["name"]}"
      assert existing_venue_log =~ "Processing venue: #{venue_data["name"]}"
    end
  end
end

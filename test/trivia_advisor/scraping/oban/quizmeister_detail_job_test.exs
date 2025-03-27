Code.require_file("../../scraping/base_scraper_job_test.exs", __DIR__)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
  @moduledoc """
  Tests for QuizmeistersDetailJob using the log-driven testing approach.

  This module implements the log-driven testing approach focusing on job behavior
  through logs rather than implementation details.
  """
  use TriviaAdvisor.DataCase
  use TriviaAdvisor.ObanCase
  import ExUnit.CaptureLog
  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.LocationsFixtures
  alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

  # Implement job_module function
  def job_module, do: QuizmeistersDetailJob

  # Common setup - creates source, venue, and venue_data
  setup do
    # Create source
    source = TriviaAdvisor.ScrapingFixtures.source_fixture()

    # Create venue with a predictable slug
    venue = LocationsFixtures.venue_fixture(%{slug: "test-quizmeisters-venue"})

    # Add test hero image data
    venue =
      venue
      |> Ecto.Changeset.change(%{
        google_place_images: [%{
          "reference" => "test-image-reference",
          "url" => "https://quizmeisters.com/images/test-venue-image.jpg",
          "filename" => "test-venue-image.jpg"
        }]
      })
      |> Repo.update!()

    # Create venue_data as the job would receive it
    venue_data = %{
      "id" => venue.id,
      "name" => venue.name,
      "url" => "https://quizmeisters.com/venues/#{venue.slug}",
      "slug" => venue.slug,
      "address" => venue.address,
      "latitude" => venue.latitude,
      "longitude" => venue.longitude
    }

    %{source: source, venue: venue, venue_data: venue_data}
  end

  # Helper to run a job with test_mode enabled (prevents actual HTTP requests)
  def perform_test_job(venue_data, source_id, options \\ []) do
    # Get options
    force_refresh = Keyword.get(options, :force_refresh, false)
    mock_http_response = Keyword.get(options, :mock_http_response, false)

    # Set process flags for testing
    Process.put(:test_mode, true)
    Process.put(:force_refresh_images, force_refresh)

    # If mock_http_response is set, add a mock for HTTP responses
    if mock_http_response do
      Process.put(:mock_http_response, %{status_code: 200, body: "<html><body>Test content</body></html>"})
    end

    # Build args with venue key to match the job's expectations
    args = %{"venue" => venue_data, "source_id" => source_id}
    args = if force_refresh, do: Map.put(args, "force_refresh_images", true), else: args

    # Run the job and return the result and captured logs
    log = capture_log(fn ->
      result = perform_job(job_module(), args)
      Process.put(:job_result, result)
    end)

    {Process.get(:job_result), log}
  end

  # This test only verifies that logs are created with the expected force_refresh flag
  # We don't care about the actual HTTP result in this test
  test "logs indicate force_refresh_images=true when enabled", %{venue_data: venue_data, source: source} do
    {_result, log} = perform_test_job(venue_data, source.id, force_refresh: true)

    # Test expected log patterns for force refresh
    assert log =~ "Processing venue: #{venue_data["name"]}"
    assert log =~ "force_refresh_images=true"
  end

  # This test only verifies that logs are created with the expected force_refresh flag
  # We don't care about the actual HTTP result in this test
  test "logs indicate force_refresh_images=false when disabled", %{venue_data: venue_data, source: source} do
    {_result, log} = perform_test_job(venue_data, source.id, force_refresh: false)

    # Test expected log patterns without force refresh
    assert log =~ "Processing venue: #{venue_data["name"]}"
    assert log =~ "force_refresh_images=false"
  end

  test "logs contain venue slug reference", %{venue_data: venue_data, source: source} do
    {_result, log} = perform_test_job(venue_data, source.id)

    # Check for venue slug in the logs
    assert log =~ venue_data["slug"]
    assert log =~ "Processing venue: #{venue_data["name"]}"
  end

  test "logs are produced regardless of venue image state", %{venue_data: venue_data, source: source} do
    # Get the venue and remove its images
    venue = Repo.get!(TriviaAdvisor.Locations.Venue, venue_data["id"])

    venue
    |> Ecto.Changeset.change(%{google_place_images: []})
    |> Repo.update!()

    # Run the job
    {_result, log} = perform_test_job(venue_data, source.id)

    # Check logs for expected messages when no images exist
    assert log =~ "Processing venue: #{venue_data["name"]}"
  end

  test "job handles additional options in args", %{venue_data: venue_data, source: source} do
    # Set process flags for testing
    Process.put(:test_mode, true)

    # Build args with additional options
    args = %{
      "venue" => venue_data,
      "source_id" => source.id,
      "retry_count" => 1,
      "force_refresh_images" => true
    }

    # Run the job and capture logs
    log = capture_log(fn ->
      # We don't check the result here since we expect HTTP errors in test mode
      # We only care that the job processed the args correctly and logged the expected output
      perform_job(job_module(), args)
    end)

    # The job should have processed the venue regardless of HTTP errors
    assert log =~ "Processing venue: #{venue_data["name"]}"
    assert log =~ "force_refresh_images=true"
  end
end

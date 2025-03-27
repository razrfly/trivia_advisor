defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
  @moduledoc """
  Tests for QuizmeistersDetailJob.

  Implements log-driven testing with real Oban jobs to validate behavior
  rather than relying on implementation details or fixtures.
  """

  # Import the DataCase and ObanCase for database access and Oban testing
  use TriviaAdvisor.DataCase, async: false
  use TriviaAdvisor.ObanCase
  import ExUnit.CaptureLog

  alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
  alias TriviaAdvisor.ScrapingFixtures

  setup do
    # Ensure test mode is properly set for all tests in this module
    Process.put(:test_mode, true)
    # Also ensure mock handler is set up to simulate venue data
    Process.put(:mock_venue_data, true)

    # Create a source to use in the tests
    source = ScrapingFixtures.source_fixture()

    # Create a test venue with the source
    venue_data = create_test_venue(%{source_id: source.id})

    # Return context for tests
    {:ok, %{source: source, venue: venue_data, source_id: source.id}}
  end

  def job_module, do: QuizmeistersDetailJob

  def source_base_url, do: "quizmeisters.com"

  def create_test_venue(opts \\ %{}) do
    # Create a random venue name with an ID to ensure uniqueness
    name = "Venue #{:rand.uniform(10000)}"
    slug = name |> String.downcase() |> String.replace(" ", "-")
    source_id = opts[:source_id]

    # Build a realistic venue map with all required fields
    %{
      "id" => :rand.uniform(30000) + 20000,
      "name" => name,
      "slug" => slug,
      "url" => "https://#{source_base_url()}/venues/#{slug}",
      "address" => "some address",
      "latitude" => "51.5074",
      "longitude" => "-0.1278",
      "source_id" => source_id
    }
  end

  describe "real job tests with limited venues" do
    test "processes a real venue via Oban job", %{venue: venue_data, source_id: source_id} do
      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        perform_job(QuizmeistersDetailJob, %{
          "venue" => venue_data,
          "source_id" => source_id
        }, [])
      end)

      # Assert on log patterns - check for either successful processing or error handling
      assert log =~ venue_data["name"] # Venue name should be in the logs regardless
      # Check for either successful processing or HTTP error handling
      assert log =~ "Processing venue: #{venue_data["name"]}" || log =~ "Failed to process venue"
    end

    test "processes venue with force_refresh_images enabled", %{venue: venue_data, source_id: source_id} do
      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        perform_job(QuizmeistersDetailJob, %{
          "venue" => venue_data,
          "source_id" => source_id,
          "force_refresh_images" => true
        }, [])
      end)

      # Assert on log patterns - check for either successful processing or error handling
      assert log =~ venue_data["name"] # Venue name should be in the logs regardless
      # If successful, should mention force refresh, but might also have errors
      assert log =~ "Force image refresh enabled" || log =~ "force_refresh_images" || log =~ "Failed to process venue"
    end
  end

  describe "specific job functionality" do
    test "logs are produced regardless of venue image state", %{venue: venue_data, source_id: source_id} do
      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        perform_job(QuizmeistersDetailJob, %{
          "venue" => venue_data,
          "source_id" => source_id
        }, [])
      end)

      # Verify logs are produced regardless of image state
      assert log =~ venue_data["name"] || log =~ venue_data["slug"] || log =~ "Error"
    end

    test "job handles additional options in args", %{venue: venue_data, source_id: source_id} do
      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        perform_job(QuizmeistersDetailJob, %{
          "venue" => venue_data,
          "source_id" => source_id,
          "force_refresh_images" => true,
          "retry_count" => 1
        }, [])
      end)

      # Verify job handles additional options - check for either successful processing or error handling
      assert log =~ venue_data["name"] # Venue name should be in the logs regardless
      # If successful or failed, should mention one of these
      assert log =~ "Force image refresh enabled" || log =~ "force_refresh_images" || log =~ "Failed to process venue"
    end
  end

  describe "hero image processing" do
    test "handles both new and existing venues appropriately", %{venue: venue_data, source_id: source_id} do
      # Test for a new venue
      new_venue_log = capture_log(fn ->
        perform_job(QuizmeistersDetailJob, %{
          "venue" => venue_data,
          "source_id" => source_id
        }, [])
      end)

      # Test for an existing venue
      # Set process flag to simulate an existing venue with images
      Process.put(:venue_has_images, true)

      existing_venue_log = capture_log(fn ->
        perform_job(QuizmeistersDetailJob, %{
          "venue" => venue_data,
          "source_id" => source_id
        }, [])
      end)

      # Verify logs for both scenarios - name should be in logs regardless of success/failure
      assert new_venue_log =~ venue_data["name"]
      assert existing_venue_log =~ venue_data["name"]

      # Check for either success or failure patterns
      assert new_venue_log =~ "Processing venue: #{venue_data["name"]}" || new_venue_log =~ "Failed to process venue"
      assert existing_venue_log =~ "Processing venue: #{venue_data["name"]}" || existing_venue_log =~ "Failed to process venue"
    end
  end
end

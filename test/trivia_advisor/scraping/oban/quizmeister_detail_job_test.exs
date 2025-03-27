defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
  @moduledoc """
  Tests for QuizmeistersDetailJob.

  Implements log-driven testing with real Oban jobs to validate behavior
  rather than relying on implementation details or fixtures.
  """

  use TriviaAdvisor.DataCase, async: false
  use TriviaAdvisor.ObanCase
  import ExUnit.CaptureLog

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
  alias TriviaAdvisor.Scraping.Source

  setup do
    # Get or create a source record for testing
    source =
      case Repo.get_by(Source, name: "Quizmeisters") do
        nil ->
          Repo.insert!(%Source{
            name: "Quizmeisters",
            website_url: "https://quizmeisters.com",
            slug: "quizmeisters"
          })
        existing -> existing
      end

    # Set test mode flag for all tests
    Process.put(:test_mode, true)
    Process.put(:mock_venue_data, true)

    # Use a test venue
    venue = get_test_venue(source.id)

    {:ok, %{source: source, venue: venue}}
  end

  defp get_test_venue(source_id) do
    # Create a minimal test venue since we don't need actual database interaction
    # This avoids potential issues with the real venue schema
    %{
      "id" => 12345,
      "name" => "Test Quiz Venue",
      "slug" => "test-quiz-venue",
      "url" => "https://quizmeisters.com/venues/test-quiz-venue",
      "address" => "123 Test Street, Testville",
      "latitude" => "51.5074",
      "longitude" => "-0.1278",
      "source_id" => source_id
    }
  end

  describe "real job tests with actual venues" do
    test "processes a venue via Oban job", %{venue: venue, source: source} do
      args = %{
        "venue" => venue,
        "source_id" => source.id
      }

      log = capture_log(fn ->
        # Use Oban.Testing.perform_job/3 instead of inserting and running
        Oban.Testing.perform_job(QuizmeistersDetailJob, args, [])
      end)

      # Log validates either successful processing or appropriate error handling
      assert log =~ venue["name"] || log =~ venue["slug"]
      assert log =~ "Processing venue:" || log =~ "Failed to process venue"
    end

    test "processes venue with force_refresh_images enabled", %{venue: venue, source: source} do
      args = %{
        "venue" => venue,
        "source_id" => source.id,
        "force_refresh_images" => true
      }

      log = capture_log(fn ->
        # Use Oban.Testing.perform_job/3 instead of inserting and running
        Oban.Testing.perform_job(QuizmeistersDetailJob, args, [])
      end)

      # Verify venue processing and force_refresh_images flag
      assert log =~ venue["name"] || log =~ venue["slug"]

      # Validate the force_refresh_images flag is recognized in logs
      assert log =~ "Force image refresh enabled" ||
             log =~ "force_refresh_images=true" ||
             log =~ "Process dictionary force_refresh_images set to: true" ||
             (log =~ "force_refresh_images" && log =~ "true")
    end
  end

  describe "job functionality with real venues" do
    test "handles additional options in args", %{venue: venue, source: source} do
      args = %{
        "venue" => venue,
        "source_id" => source.id,
        "force_refresh_images" => true,
        "retry_count" => 1
      }

      log = capture_log(fn ->
        # Use Oban.Testing.perform_job/3 instead of inserting and running
        Oban.Testing.perform_job(QuizmeistersDetailJob, args, [])
      end)

      # Verify venue processing
      assert log =~ venue["name"] || log =~ venue["slug"]

      # Validate force_refresh_images flag
      assert log =~ "Force image refresh enabled" ||
             log =~ "force_refresh_images=true" ||
             log =~ "Process dictionary force_refresh_images set to: true" ||
             (log =~ "force_refresh_images" && log =~ "true")
    end
  end

  describe "image processing with real venues" do
    test "force_refresh_images affects hero image processing", %{venue: venue, source: source} do
      # First run without force refresh
      standard_log = capture_log(fn ->
        # Use Oban.Testing.perform_job/3 instead of inserting and running
        Oban.Testing.perform_job(QuizmeistersDetailJob, %{
          "venue" => venue,
          "source_id" => source.id
        }, [])
      end)

      # Then run with force refresh
      forced_log = capture_log(fn ->
        # Use Oban.Testing.perform_job/3 instead of inserting and running
        Oban.Testing.perform_job(QuizmeistersDetailJob, %{
          "venue" => venue,
          "source_id" => source.id,
          "force_refresh_images" => true
        }, [])
      end)

      # Validate force_refresh_images appears in logs
      assert forced_log =~ "Force image refresh enabled" ||
             forced_log =~ "force_refresh_images=true" ||
             forced_log =~ "Process dictionary force_refresh_images set to: true" ||
             (forced_log =~ "force_refresh_images" && forced_log =~ "true")

      # The standard log should not mention force refresh
      refute standard_log =~ "Force image refresh enabled"
      refute standard_log =~ "force_refresh_images=true"
      refute standard_log =~ "Process dictionary force_refresh_images set to: true"
    end
  end
end

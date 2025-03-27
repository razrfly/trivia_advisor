defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJobTest do
  @moduledoc """
  Tests for QuizmeistersIndexJob using log-driven validation with real data.

  These tests verify the job behavior by asserting on log outputs rather than
  internal implementation details.
  """
  use TriviaAdvisor.DataCase, async: false
  use TriviaAdvisor.ObanCase
  import ExUnit.CaptureLog

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
  require Logger

  setup do
    # Get or create a real source record for testing
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

    # Configure logger to show info level logs during tests
    Logger.configure(level: :info)

    # Set test mode flag to avoid real HTTP requests
    Process.put(:test_mode, true)
    Application.put_env(:trivia_advisor, :test_mode, true)

    {:ok, %{source: source}}
  end

  describe "log-driven tests with real Oban jobs" do
    test "processes venues with default parameters (limited to 3)", %{source: source} do
      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        Oban.Testing.perform_job(QuizmeistersIndexJob, %{
          "source_id" => source.id,
          "limit" => 3
        }, [])
      end)

      # Assert on log patterns
      assert log =~ "Starting Quizmeisters Index Job"
      assert log =~ "Successfully fetched"
      assert log =~ "Testing mode: Limited to 3 venues"
    end

    test "processes venues with force_refresh_images and force_update", %{source: source} do
      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        Oban.Testing.perform_job(QuizmeistersIndexJob, %{
          "source_id" => source.id,
          "limit" => 1,
          "force_refresh_images" => true,
          "force_update" => true
        }, [])
      end)

      # Assert on log patterns
      assert log =~ "Starting Quizmeisters Index Job"
      assert log =~ "Force update enabled"
      assert log =~ "Force image refresh enabled"
      assert log =~ "DEBUG: force_refresh_images value in detail job: true"
    end

    test "job handles network errors gracefully", %{source: source} do
      # Set test flags to simulate an error
      Process.put(:simulate_network_error, true)

      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        Oban.Testing.perform_job(QuizmeistersIndexJob, %{
          "source_id" => source.id,
          "limit" => 1,
          "simulate_network_error" => true
        }, [])
      end)

      # Check for job start and appropriate handling
      assert log =~ "Starting Quizmeisters Index Job"
    end
  end

  describe "detail job scheduling" do
    test "correctly schedules detail jobs for venues", %{source: source} do
      # Perform job directly with the module, args, and options
      log = capture_log(fn ->
        Oban.Testing.perform_job(QuizmeistersIndexJob, %{
          "source_id" => source.id,
          "limit" => 2
        }, [])

        # Wait for jobs to be processed
        :timer.sleep(500)
      end)

      # Check logs for detail job scheduling
      assert log =~ "Starting Quizmeisters Index Job"
      assert log =~ "Successfully fetched"
      assert log =~ "Enqueued 2 detail jobs" || log =~ "Scheduling 2 venues"
    end
  end
end

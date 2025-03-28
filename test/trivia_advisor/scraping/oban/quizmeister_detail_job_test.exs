defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
  @moduledoc """
  Tests for QuizmeistersDetailJob.

  This tests REAL job execution with actual data from the database.
  No mocking, no test fixtures - just actual jobs and actual data.
  """

  # Configure Logger to show all log messages during tests
  require Logger
  Logger.configure(level: :debug)

  use TriviaAdvisor.DataCase, async: false
  use TriviaAdvisor.ObanCase
  import ExUnit.CaptureLog

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob

  setup do
    # Get or create a real source record - only database interaction, no test fixtures
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

    # Set test mode flag in environment for test runs
    Application.put_env(:trivia_advisor, :test_mode, true)
    Process.put(:test_mode, true)

    {:ok, %{source: source}}
  end

  describe "real job execution with force_refresh_images flag" do
    test "force_refresh_images flag is properly processed", %{source: source} do
      # First run the index job to get real venues
      index_log = capture_log(fn ->
        {:ok, _index_job} = Oban.insert(QuizmeistersIndexJob.new(%{
          "source_id" => source.id,
          "limit" => 3
        }))

        # Wait for the job to complete
        :timer.sleep(2000)
      end)

      # Log should show that the index job ran successfully
      assert index_log =~ "Starting Quizmeisters Index Job"

      # Extract a real venue ID from the log to use in detail job
      # This ensures we're using real data throughout

      # First, run index with force_refresh_images disabled
      standard_log = capture_log(fn ->
        # Let the regular job queue handle scheduling the detail jobs
        # The index job will automatically create detail jobs with real venues
        {:ok, _job} = Oban.insert(QuizmeistersIndexJob.new(%{
          "source_id" => source.id,
          "limit" => 1
        }))

        # Wait for jobs to run
        :timer.sleep(3000)
      end)

      # Then run with force_refresh_images enabled
      forced_log = capture_log(fn ->
        {:ok, _job} = Oban.insert(QuizmeistersIndexJob.new(%{
          "source_id" => source.id,
          "force_refresh_images" => true,
          "limit" => 1
        }))

        # Wait for jobs to run
        :timer.sleep(3000)
      end)

      # Print the captured logs so we can see them on the console
      IO.puts("\n\n===== CAPTURED LOGS (force_refresh_images=true) =====\n")
      IO.puts(forced_log)
      IO.puts("\n===== END CAPTURED LOGS =====\n")

      # Validate behavior through logs
      refute standard_log =~ "Force image refresh enabled"
      assert forced_log =~ "Force image refresh enabled"
      assert forced_log =~ "force_refresh_images=true"
      assert forced_log =~ "Process dictionary force_refresh_images set to: true"
    end
  end

  describe "end to end workflow test" do
    test "index job schedules detail jobs correctly", %{source: source} do
      log = capture_log(fn ->
        # Insert and run a real index job with a small limit
        {:ok, _job} = Oban.insert(QuizmeistersIndexJob.new(%{
          "source_id" => source.id,
          "force_refresh_images" => true,
          "force_update" => true,
          "limit" => 3
        }))

        # Wait for the job to complete
        :timer.sleep(5000)
      end)

      # Print the captured logs so we can see them on the console
      IO.puts("\n\n===== CAPTURED LOGS (end-to-end workflow) =====\n")
      IO.puts(log)
      IO.puts("\n===== END CAPTURED LOGS =====\n")

      # Validate the job ran successfully
      assert log =~ "Starting Quizmeisters Index Job"

      # The index job should have scheduled detail jobs
      assert log =~ "Scheduling" && log =~ "venues"

      # Specific force_refresh_images handling
      assert log =~ "Force image refresh enabled"
      assert log =~ "force_refresh_images=true"
      assert log =~ "DEBUG: force_refresh_images value in detail job: true"
    end
  end
end

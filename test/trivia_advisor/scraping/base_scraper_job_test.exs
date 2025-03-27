defmodule TriviaAdvisor.Scraping.BaseScraperJobTest do
  @moduledoc """
  Base module for testing scraper jobs using a log-driven testing approach with real data.

  This module focuses on running actual Oban jobs and validating their behavior through logs,
  with no mocking or test fixtures. All venue data should come directly from real job execution
  or existing database records.

  Concrete test modules must implement the `job_module` callback.
  """
  use ExUnit.CaseTemplate
  import ExUnit.CaptureLog
  alias TriviaAdvisor.ScrapingFixtures

  # Required callbacks
  @callback job_module() :: module()

  # Optional callbacks with defaults
  @callback ensure_source() :: map()

  @optional_callbacks [
    ensure_source: 0
  ]

  using do
    quote do
      # Use DataCase for database access and ObanCase for Oban testing
      use TriviaAdvisor.DataCase, async: false
      use TriviaAdvisor.ObanCase

      @behaviour TriviaAdvisor.Scraping.BaseScraperJobTest
      import TriviaAdvisor.Scraping.BaseScraperJobTest
      import ExUnit.CaptureLog

      # Setup for tests
      setup do
        # Get or create a source to use in the tests
        source = ensure_source()

        # Return context for tests
        {:ok, %{source: source, source_id: source.id}}
      end
    end
  end

  @doc """
  Performs the test job, capturing logs and returning the job result and logs.
  """
  def perform_test_job(job_module, venue_data, opts \\ %{}) do
    log = capture_log(fn ->
      # Create job args properly
      args = %{
        "venue" => venue_data,
        "source_id" => venue_data["source_id"] || venue_data[:source_id]
      } |> Map.merge(opts)

      # Use perform_job/3 with module, args, and options
      Oban.Testing.perform_job(job_module, args, [])
    end)

    # Return both the job result and the logs
    {nil, log}
  end

  @doc """
  Runs a real job using Oban with a specified limit on results to keep tests manageable.
  """
  def run_real_job_with_limit(job_module, limit \\ 3, opts \\ %{}) do
    args = Map.merge(%{"limit" => limit}, opts)

    # Capture logs during job execution using perform_job/3
    log = capture_log(fn ->
      # Use perform_job/3 with module, args, and options
      Oban.Testing.perform_job(job_module, args, [])
    end)

    # Return both the job result and the logs
    {nil, log}
  end

  @doc """
  Gets or creates a source record for testing.
  Defaults to using a real source from the database or creates one if needed.
  """
  def ensure_source do
    ScrapingFixtures.source_fixture()
  end

  # Common test cases that can be reused across job test modules

  @doc """
  Common test to verify job properly processes the force_refresh_images flag.
  """
  def test_job_processes_with_different_force_refresh_settings(job_module, venue_data) do
    # Test without force_refresh
    {_, log_without_force} = perform_test_job(job_module, venue_data)
    assert log_without_force =~ "Processing venue"
    refute log_without_force =~ "Force image refresh enabled"

    # Test with force_refresh
    {_, log_with_force} = perform_test_job(job_module, venue_data, %{force_refresh_images: true})
    assert log_with_force =~ "Processing venue"
    assert log_with_force =~ "Force image refresh enabled" ||
           log_with_force =~ "force_refresh_images=true" ||
           log_with_force =~ "Process dictionary force_refresh_images set to: true"
  end

  @doc """
  Common test to ensure logs contain venue details for validation.
  """
  def test_logs_contain_venue_details(job_module, venue_data) do
    {_, log} = perform_test_job(job_module, venue_data)

    # Check for venue name or slug in logs
    assert log =~ venue_data["name"] ||
           log =~ (venue_data["slug"] || "") ||
           log =~ "Processing venue"
  end
end

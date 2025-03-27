defmodule TriviaAdvisor.Scraping.BaseScraperJobTest do
  @moduledoc """
  Base module for testing scraper jobs using a log-driven testing approach.

  This module focuses on running actual Oban jobs and validating their behavior through logs,
  rather than mocking implementation details.

  Concrete test modules must implement the `job_module` callback and may optionally override
  other callbacks like `create_test_venue`.
  """
  use ExUnit.CaseTemplate
  import ExUnit.CaptureLog
  alias TriviaAdvisor.ScrapingFixtures

  # Required callbacks
  @callback job_module() :: module()

  # Optional callbacks with defaults
  @callback source_base_url() :: String.t()
  @callback create_test_venue(map()) :: map()
  @callback create_test_source() :: map()

  @optional_callbacks [
    source_base_url: 0,
    create_test_venue: 1,
    create_test_source: 0
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
        # Create a source to use in the tests
        source = create_test_source()

        # Create a test venue with the source
        venue_data = create_test_venue(%{source_id: source.id})

        # Return context for tests
        {:ok, %{source: source, venue: venue_data, source_id: source.id}}
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
  Creates a test source fixture with a realistic URL.
  Defaults to using a real source from the fixtures.
  """
  def create_test_source do
    ScrapingFixtures.source_fixture()
  end

  @doc """
  Creates a test venue with a realistic slug based on the venue name.
  """
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

  @doc """
  Default base URL for the source.
  This should be overridden by implementing modules.
  """
  def source_base_url do
    "example.com"
  end

  # Common test cases that can be reused across job test modules

  @doc """
  Common test to verify job processes with different force_refresh settings.
  """
  def test_job_processes_with_different_force_refresh_settings(job_module, venue_data) do
    # Test without force_refresh
    {_, log_without_force} = perform_test_job(job_module, venue_data)
    assert log_without_force =~ "Processing venue"

    # Test with force_refresh
    {_, log_with_force} = perform_test_job(job_module, venue_data, %{force_refresh_images: true})
    assert log_with_force =~ "Processing venue"
    assert log_with_force =~ "force_refresh_images: true"
  end

  @doc """
  Common test to ensure logs contain venue slug and name.
  """
  def test_logs_contain_venue_details(job_module, venue_data) do
    {_, log} = perform_test_job(job_module, venue_data)
    assert log =~ venue_data["slug"]
    assert log =~ venue_data["name"]
  end
end

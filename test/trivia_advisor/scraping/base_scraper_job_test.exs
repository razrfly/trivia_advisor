defmodule TriviaAdvisor.Scraping.BaseScraperJobTest do
  @moduledoc """
  Base module for testing scraper jobs using log-driven testing.

  This module defines common test setups and behavior for testing scraper jobs,
  focusing on validating job behavior through logs rather than implementation details.

  To use this module:
  1. Define a concrete test module that uses it
  2. Implement the required callbacks
  3. Call the provided test macros or use the helper functions in your tests

  Example:
  ```elixir
  defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
    use TriviaAdvisor.Scraping.BaseScraperJobTest

    # Implement required callbacks
    @impl true
    def job_module, do: TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

    @impl true
    def create_test_venue do
      # Implementation to create a test venue
    end
  end
  """

  # Define the behavior with required callbacks
  @callback job_module() :: module()
  @callback create_test_venue() :: {map(), map()}
  @callback create_test_source() :: map()

  defmacro __using__(_opts) do
    quote do
      use TriviaAdvisor.DataCase
      use TriviaAdvisor.ObanCase
      import ExUnit.CaptureLog
      require Logger

      # Implement the behavior
      @behaviour TriviaAdvisor.Scraping.BaseScraperJobTest

      # Default implementations that can be overridden
      @impl true
      def create_test_source do
        TriviaAdvisor.ScrapingFixtures.source_fixture()
      end

      # Common setup - creates source, venue, and venue_data
      setup do
        # Create source
        source = create_test_source()

        # Create venue and generate venue_data
        {venue, venue_data} = create_test_venue()

        # Ensure source_id is in venue_data
        venue_data = Map.put(venue_data, "source_id", source.id)

        %{source: source, venue: venue, venue_data: venue_data}
      end

      # Helper to run a job with test_mode enabled (prevents actual HTTP requests)
      def perform_test_job(args, options \\ []) do
        # Get options
        force_refresh = Keyword.get(options, :force_refresh, false)

        # Set process flags for testing
        Process.put(:test_mode, true)
        Process.put(:force_refresh_images, force_refresh)

        # Run the job and return the result and captured logs
        log = capture_log(fn ->
          result = perform_job(job_module(), args)
          Process.put(:job_result, result)
        end)

        {Process.get(:job_result), log}
      end

      # Common test cases that can be used by all scrapers

      test "job processes venue with force_refresh_images true", %{venue_data: venue_data} do
        args = %{"venue_data" => venue_data, "source_id" => venue_data["source_id"]}
        {result, log} = perform_test_job(args, force_refresh: true)

        # Test job completed successfully
        assert {:ok, _} = result

        # Test expected log patterns for force refresh
        assert log =~ "Processing venue: #{venue_data["name"]}"
        assert log =~ "force_refresh_images=true"
      end

      test "job processes venue with force_refresh_images false", %{venue_data: venue_data} do
        args = %{"venue_data" => venue_data, "source_id" => venue_data["source_id"]}
        {result, log} = perform_test_job(args, force_refresh: false)

        # Test job completed successfully
        assert {:ok, _} = result

        # Test expected log patterns without force refresh
        assert log =~ "Processing venue: #{venue_data["name"]}"
        assert log =~ "force_refresh_images=false"
      end

      # Define more common test cases here...
    end
  end
end

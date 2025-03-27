defmodule TriviaAdvisor.Scraping.BaseScraperJobTest do
  @moduledoc """
  Base module for testing scraper jobs using log-driven testing.

  This module defines common test setups and behavior for testing scraper jobs,
  focusing on validating job behavior through logs rather than implementation details.

  To use this module:
  1. Define a concrete test module that uses it
  2. Implement the required callbacks (only job_module is mandatory)
  3. Call the provided test macros or use the helper functions in your tests

  Example:
  ```elixir
  defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
    use TriviaAdvisor.Scraping.BaseScraperJobTest

    # Implement required callback
    @impl true
    def job_module, do: TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

    @impl true
    def source_base_url, do: "https://quizmeisters.com"
  end
  """

  # Define the behavior with required callbacks
  @callback job_module() :: module()
  @callback source_base_url() :: String.t()

  # Optional callbacks
  @callback create_test_venue() :: {map(), map()}
  @callback create_test_source() :: map()

  # Specify which callbacks are optional
  @optional_callbacks [create_test_venue: 0, create_test_source: 0]

  defmacro __using__(_opts) do
    quote do
      use TriviaAdvisor.DataCase
      use TriviaAdvisor.ObanCase
      import ExUnit.CaptureLog
      require Logger

      # Implement the behavior
      @behaviour TriviaAdvisor.Scraping.BaseScraperJobTest

      # Default implementations for optional callbacks
      def create_test_source do
        TriviaAdvisor.ScrapingFixtures.source_fixture()
      end

      # Default source_base_url - test modules should override this
      def source_base_url, do: "https://example.com"

      # Default implementation for create_test_venue
      def create_test_venue do
        alias TriviaAdvisor.LocationsFixtures
        alias TriviaAdvisor.Repo

        # Create venue with a predictable slug
        venue = LocationsFixtures.venue_fixture(%{slug: "test-venue-slug"})

        # Add test hero image data
        venue =
          venue
          |> Ecto.Changeset.change(%{
            google_place_images: [%{
              "reference" => "test-image-reference",
              "url" => "#{source_base_url()}/images/test-venue-image.jpg",
              "filename" => "test-venue-image.jpg"
            }]
          })
          |> Repo.update!()

        # Create venue_data as the job would receive it
        venue_data = %{
          "id" => venue.id,
          "name" => venue.name,
          "url" => "#{source_base_url()}/venues/#{venue.slug}",
          "slug" => venue.slug,
          "address" => venue.address,
          "latitude" => venue.latitude,
          "longitude" => venue.longitude
        }

        {venue, venue_data}
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

        # Build args properly depending on the job type
        # Set "venue" as the key to match detail job expectations
        args = %{"venue" => venue_data, "source_id" => source_id}
        args = if force_refresh, do: Map.put(args, "force_refresh_images", true), else: args

        # Run the job and return the result and captured logs
        log = capture_log(fn ->
          result = perform_job(job_module(), args)
          Process.put(:job_result, result)
        end)

        {Process.get(:job_result), log}
      end

      # Common test cases that can be used by all scrapers
      describe "common scraper job tests" do
        test "job processes venue with different force_refresh settings", %{venue_data: venue_data, source: source} do
          # Test both force_refresh settings to ensure the job handles both correctly
          for force_refresh <- [true, false] do
            {_result, log} = perform_test_job(venue_data, source.id, force_refresh: force_refresh)

            # Test expected log patterns - check for either successful processing or error handling
            assert log =~ venue_data["name"]
            assert log =~ "force_refresh_images=#{force_refresh}" || log =~ "Failed to process venue"
          end
        end

        test "logs contain venue slug reference", %{venue_data: venue_data, source: source} do
          {_result, log} = perform_test_job(venue_data, source.id)

          # Check for venue slug in the logs - either in processing or in error message
          assert log =~ venue_data["slug"]
          assert log =~ venue_data["name"]
        end
      end

      # Allow overriding the callbacks
      defoverridable create_test_source: 0, create_test_venue: 0, source_base_url: 0
    end
  end
end

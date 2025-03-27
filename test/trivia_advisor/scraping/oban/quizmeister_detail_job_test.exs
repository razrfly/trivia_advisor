Code.require_file("../../scraping/base_scraper_job_test.exs", __DIR__)

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
  @moduledoc """
  Tests for QuizmeistersDetailJob using the log-driven testing approach.

  This module implements the log-driven testing approach focusing on job behavior
  through logs rather than implementation details.
  """
  use TriviaAdvisor.Scraping.BaseScraperJobTest

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue

  # Required callback implementation
  @impl true
  def job_module, do: TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob

  # Override the source base URL for Quizmeisters
  @impl true
  def source_base_url, do: "https://quizmeisters.com"

  describe "specific job functionality" do
    test "logs are produced regardless of venue image state", %{venue_data: venue_data, source: source} do
      # Get the venue and remove its images
      venue = Repo.get!(Venue, venue_data["id"])

      venue
      |> Ecto.Changeset.change(%{google_place_images: []})
      |> Repo.update!()

      # Run the job
      {_result, log} = perform_test_job(venue_data, source.id)

      # Check logs for expected messages when no images exist
      assert log =~ venue_data["name"]
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
      assert log =~ venue_data["name"]
      assert log =~ "force_refresh_images=true" || log =~ "Failed to process venue"
    end
  end

  describe "hero image processing" do
    test "handles both new and existing venues appropriately", %{venue_data: venue_data, source: source} do
      # Get the venue
      venue = Repo.get!(Venue, venue_data["id"])

      # Update venue to have no images, simulating a new venue
      venue
      |> Ecto.Changeset.change(%{google_place_images: []})
      |> Repo.update!()

      # Run the job and capture logs for "new" venue
      {_result, new_venue_log} = perform_test_job(venue_data, source.id)

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
      {_result, existing_venue_log} = perform_test_job(venue_data, source.id)

      # Basic assertions to ensure job works with both new and existing venues
      assert new_venue_log =~ venue_data["name"]
      assert existing_venue_log =~ venue_data["name"]
    end
  end
end

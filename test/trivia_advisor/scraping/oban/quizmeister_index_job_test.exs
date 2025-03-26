defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJobTest do
  use TriviaAdvisor.DataCase
  use TriviaAdvisor.ObanCase
  import Mock
  require Logger

  alias TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob
  alias TriviaAdvisor.ScrapingFixtures

  setup do
    # Ensure we can see logs in tests
    Logger.configure(level: :info)

    # Create the source record needed by the job
    source = ScrapingFixtures.source_fixture()
    %{source: source}
  end

  describe "perform/1" do
    test "processes quizmeisters with default parameters", %{source: _source} do
      # Mock the HTTP call to return sample data
      with_mock HTTPoison, [get: fn _url, _headers, _options ->
        body = Jason.encode!(%{"results" => %{"locations" => []}})
        {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      end] do
        log = capture_log(fn ->
          perform_job(QuizmeistersIndexJob, %{})
        end)

        assert log =~ "Starting Quizmeisters Index Job"
        assert log =~ "Successfully fetched 0 venues"
      end
    end

    test "processes quizmeisters with force_update and limit", %{source: _source} do
      # Mock the HTTP call to return sample data
      with_mock HTTPoison, [get: fn _url, _headers, _options ->
        body = Jason.encode!(%{"results" => %{"locations" => []}})
        {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      end] do
        log = capture_log(fn ->
          perform_job(QuizmeistersIndexJob, %{
            "force_refresh_images" => true,
            "force_update" => true,
            "limit" => 1
          })
        end)

        assert log =~ "Starting Quizmeisters Index Job"
        assert log =~ "Force update enabled"
        assert log =~ "Force image refresh enabled"
        assert log =~ "Testing mode: Limited to"
      end
    end

    test "handles errors gracefully", %{source: _source} do
      # Mock the HTTP call to fail
      with_mock HTTPoison, [get: fn _url, _headers, _options ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end] do
        log = capture_log(fn ->
          perform_job(QuizmeistersIndexJob, %{})
        end)

        assert log =~ "Failed to fetch Quizmeisters venues"
      end
    end
  end
end

defmodule TriviaAdvisor.Scraping.Scrapers.QuestionOne do
  @moduledoc """
  Scraper for QuestionOne venues and events.
  """

  alias TriviaAdvisor.Scraping.{ScrapeLog, Source}
  alias TriviaAdvisor.Repo

  @base_url "https://questionone.com"
  @venues_url "#{@base_url}/venues/"

  @doc """
  Main entry point for the scraper.
  """
  def run do
    source = get_source()

    {:ok, log} = create_scrape_log(source)

    try do
      case fetch_venues_page() do
        {:ok, body} ->
          IO.puts "Successfully fetched venues page"
          IO.inspect(String.slice(body, 0..500), label: "First 500 chars")
          update_scrape_log(log, %{success: true})
          {:ok, log}

        {:error, reason} ->
          update_scrape_log(log, %{
            success: false,
            error: %{message: "Failed to fetch venues: #{inspect(reason)}"}
          })
          {:error, reason}
      end
    rescue
      e ->
        update_scrape_log(log, %{
          success: false,
          error: %{
            message: Exception.message(e),
            stacktrace: __STACKTRACE__
          }
        })
        {:error, e}
    end
  end

  defp fetch_venues_page do
    case HTTPoison.get(@venues_url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp get_source do
    Repo.get_by!(Source, website_url: @base_url)
  end

  defp create_scrape_log(source) do
    %ScrapeLog{}
    |> ScrapeLog.changeset(%{
      source_id: source.id,
      success: false,
      metadata: %{
        started_at: DateTime.utc_now(),
        scraper_version: "1.0.0"
      }
    })
    |> Repo.insert()
  end

  defp update_scrape_log(log, attrs) do
    log
    |> ScrapeLog.changeset(attrs)
    |> Repo.update()
  end
end

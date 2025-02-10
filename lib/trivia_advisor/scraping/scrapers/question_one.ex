defmodule TriviaAdvisor.Scraping.Scrapers.QuestionOne do
  @moduledoc """
  Scraper for QuestionOne venues and events.
  """

  alias TriviaAdvisor.Scraping.{ScrapeLog, Source}
  alias TriviaAdvisor.Repo
  require Logger

  @base_url "https://questionone.com"
  @feed_url "#{@base_url}/venues/feed/"

  @doc """
  Main entry point for the scraper.
  """
  def run do
    try do
      source = Repo.get_by!(Source, website_url: @base_url)
      {:ok, log} = create_scrape_log(source)

      Logger.info("Starting RSS feed scrape")
      venues = scrape_feed(1, [])
      venue_count = length(venues)
      Logger.info("Completed scraping #{venue_count} total venues")

      update_scrape_log(log, %{
        success: true,
        event_count: venue_count,
        metadata: Map.merge(log.metadata, %{
          total_venues: venue_count,
          venues: venues,
          completed_at: DateTime.utc_now()
        })
      })

      {:ok, venues}
    rescue
      e ->
        Logger.error("Scraper failed: #{Exception.message(e)}")
        {:error, e}
    end
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

  defp scrape_feed(page, acc) do
    url = if page == 1, do: @feed_url, else: "#{@feed_url}?paged=#{page}"
    Logger.info("Fetching page #{page}: #{url}")

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case parse_feed(body) do
          [] ->
            Logger.info("No venues found on page #{page}, stopping")
            acc
          venues ->
            Logger.info("Found #{length(venues)} venues on page #{page}")
            venues |> Enum.each(&log_venue/1)
            Process.sleep(1000) # Be nice to their server
            scrape_feed(page + 1, acc ++ venues)
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.info("Reached end at page #{page}")
        acc

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} on page #{page}")
        acc

      {:error, error} ->
        Logger.error("Error fetching page #{page}: #{inspect(error)}")
        acc
    end
  end

  defp parse_feed(body) do
    {:ok, document} = Floki.parse_document(body)

    document
    |> Floki.find("item")
    |> Enum.map(fn item ->
      %{
        title: item |> Floki.find("title") |> Floki.text() |> String.trim() |> HtmlEntities.decode(),
        url: item |> Floki.find("link") |> Floki.text() |> String.trim() |> clean_url()
      }
    end)
  end

  defp clean_url(url) do
    url
    |> String.split("?")
    |> List.first()
    |> String.trim()
  end

  defp log_venue(%{title: title, url: url}) do
    Logger.info("""
    Found Venue:
      Title: #{title}
      URL: #{url}
    """)
  end
end

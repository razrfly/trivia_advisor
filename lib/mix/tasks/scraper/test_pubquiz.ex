defmodule Mix.Tasks.Scraper.TestPubquiz do
  use Mix.Task
  require Logger

  @shortdoc "Test the Pubquiz scraper"
  def run(_) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    Logger.info("Testing Pubquiz scraper...")

    case TriviaAdvisor.Scraping.Scrapers.Pubquiz.Scraper.fetch_venues() do
      {:ok, venues} ->
        Logger.info("Found #{length(venues)} venues:")
        Enum.each(venues, fn venue ->
          Logger.info("#{venue.name} - #{venue.url}")
        end)

      {:error, error} ->
        Logger.error("Failed to fetch venues: #{inspect(error)}")
    end
  end
end

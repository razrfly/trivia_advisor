defmodule Mix.Tasks.Scrape.GeeksWhoDrink do
  use Mix.Task
  require Logger

  @shortdoc "Scrapes venue data from Geeks Who Drink"
  def run(_) do
    Logger.info("Starting Geeks Who Drink scraper...")

    # Ensure all dependencies are started
    Application.ensure_all_started(:trivia_advisor)

    case TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.Scraper.run() do
      {:ok, venues} ->
        Logger.info("✅ Successfully scraped #{length(venues)} venues")

      {:error, reason} ->
        Logger.error("❌ Failed to scrape venues: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end

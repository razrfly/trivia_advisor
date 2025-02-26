defmodule Mix.Tasks.Scrape.GeeksWhoDrink do
  use Mix.Task
  require Logger
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.Scraper

  @shortdoc "Scrapes Geeks Who Drink venues"
  def run(_) do
    # Start required applications
    Application.ensure_all_started(:trivia_advisor)

    # Load .env file if it exists
    if File.exists?(".env") do
      DotenvParser.load_file(".env")
      Logger.info("📝 Loaded .env file")
    end

    # Verify API key is available
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 ->
        Logger.info("🔑 API key loaded successfully")
        run_scraper()

      _ ->
        Logger.error("❌ GOOGLE_MAPS_API_KEY not found in environment")
        System.halt(1)
    end
  end

  defp run_scraper do
    case Scraper.run() do
      {:ok, venues} ->
        Logger.info("✅ Successfully scraped #{length(venues)} venues")
        :ok

      {:error, reason} ->
        Logger.error("❌ Failed to scrape venues: #{inspect(reason)}")
        System.halt(1)
    end
  end
end

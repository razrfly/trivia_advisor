defmodule Mix.Tasks.Scrape do
  use Mix.Task
  require Logger

  @shortdoc "Runs the QuestionOne scraper"

  def run(_) do
    # Start the application and its dependencies
    Mix.Task.run("app.start")

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
    Logger.info("🔄 Starting QuestionOne scraper...")

    case TriviaAdvisor.Scraping.Scrapers.QuestionOne.run() do
      {:ok, venues} ->
        Logger.info("✅ Successfully scraped #{length(venues)} venues")

      {:error, error} ->
        Logger.error("❌ Scraping failed: #{Exception.message(error)}")
        System.halt(1)
    end
  end
end

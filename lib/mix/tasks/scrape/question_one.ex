defmodule Mix.Tasks.Scrape.QuestionOne do
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

        # Set logger level to info to ensure we see all the details
        prev_log_level = Logger.level()
        :logger.set_primary_config(:level, :info)

        # Run the scraper directly instead of through Oban
        Logger.info("🔄 Starting QuestionOne scraper...")
        result = TriviaAdvisor.Scraping.Scrapers.QuestionOne.run()

        # Restore original log level
        :logger.set_primary_config(:level, prev_log_level)

        case result do
          {:ok, venues} ->
            Logger.info("✅ Successfully scraped #{length(venues)} venues")
            :ok

          {:error, error} ->
            Logger.error("❌ Scraping failed: #{inspect(error)}")
            System.halt(1)
        end

      _ ->
        Logger.error("❌ GOOGLE_MAPS_API_KEY not found in environment")
        System.halt(1)
    end
  end
end

defmodule TriviaAdvisor.Scraping.Jobs.QuestionOneJob do
  use Oban.Worker, queue: :default

  alias TriviaAdvisor.Scraping.Scrapers.QuestionOne

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Ensure logs are displayed to console (may be redundant, but to be safe)
    prev_log_level = Logger.level()
    :logger.set_primary_config(:level, :info)
    Application.put_env(:logger, :console, [format: "$time $metadata[$level] $message\n"])

    Logger.info("🔄 Starting QuestionOne scraper...")

    result = case QuestionOne.run() do
      {:ok, venues} ->
        Logger.info("✅ Successfully scraped #{length(venues)} venues")
        {:ok, venues}

      {:error, error} = err ->
        Logger.error("❌ Scraping failed: #{Exception.message(error)}")
        err
    end

    # Restore original log level
    :logger.set_primary_config(:level, prev_log_level)

    result
  end
end

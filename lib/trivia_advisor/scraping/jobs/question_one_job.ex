defmodule TriviaAdvisor.Scraping.Jobs.QuestionOneJob do
  use Oban.Worker, queue: :default

  alias TriviaAdvisor.Scraping.Scrapers.QuestionOne

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("🔄 Starting QuestionOne scraper...")

    case QuestionOne.run() do
      {:ok, venues} ->
        Logger.info("✅ Successfully scraped #{length(venues)} venues")
        {:ok, venues}

      {:error, error} = err ->
        Logger.error("❌ Scraping failed: #{Exception.message(error)}")
        err
    end
  end
end

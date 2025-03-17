defmodule Mix.Tasks.Scraper.TestPubquizIndex do
  use Mix.Task
  require Logger

  @shortdoc "Test the Pubquiz index job"
  def run(_) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    Logger.info("Testing Pubquiz index job...")

    case Oban.insert(TriviaAdvisor.Scraping.Oban.PubquizIndexJob.new(%{})) do
      {:ok, job} ->
        Logger.info("Successfully scheduled index job: #{job.id}")
        # Wait for job to complete
        Process.sleep(5000)
        Logger.info("Check Oban dashboard or logs for results")

      {:error, error} ->
        Logger.error("Failed to schedule index job: #{inspect(error)}")
    end
  end
end

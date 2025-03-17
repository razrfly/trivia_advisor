defmodule Mix.Tasks.Scraper.TestPubquizIndex do
  use Mix.Task
  require Logger

  @shortdoc "Test the Pubquiz index job with a limited number of venues"
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args, strict: [limit: :integer])
    # Default to 3 venues, but allow overriding with --limit=N argument
    limit = Keyword.get(opts, :limit, 3)

    Logger.info("🧪 Running Pubquiz Index Job TEST with limit of #{limit} venues...")

    case Oban.insert(TriviaAdvisor.Scraping.Oban.PubquizIndexJob.new(%{"limit" => limit})) do
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

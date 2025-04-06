defmodule Mix.Tasks.Scraper.TestPubquizIndex do
  use Mix.Task
  require Logger

  @shortdoc "Test the Pubquiz index job with a limited number of venues"
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args,
      strict: [
        limit: :integer,
        force_refresh_images: :boolean,
        force_update: :boolean
      ]
    )

    # Default to 3 venues, but allow overriding with --limit=N argument
    limit = Keyword.get(opts, :limit, 3)

    # Check for force_refresh_images flag
    force_refresh_images = Keyword.get(opts, :force_refresh_images, false)

    # Check for force_update flag
    force_update = Keyword.get(opts, :force_update, false)

    Logger.info("🧪 Running Pubquiz Index Job TEST with limit of #{limit} venues...")

    if force_refresh_images do
      Logger.info("⚠️ Force image refresh enabled - will refresh ALL images regardless of existing state")
    end

    if force_update do
      Logger.info("⚠️ Force update enabled - will process ALL venues regardless of last update time")
    end

    # Build job args with all flags
    job_args = %{
      "limit" => limit,
      "force_refresh_images" => force_refresh_images,
      "force_update" => force_update
    }

    Logger.info("🔍 Job args: #{inspect(job_args)}")

    case Oban.insert(TriviaAdvisor.Scraping.Oban.PubquizIndexJob.new(job_args)) do
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

defmodule Mix.Tasks.Scrape.Inquizition do
  use Mix.Task

  @shortdoc "Scrape venues from Inquizition"

  @moduledoc """
  Scrapes venue and event data from Inquizition.

  ## Examples

      mix scrape.inquizition

  For testing with limited number of venues:

      mix scrape.inquizition --limit=3
  """

  def run(args) do
    # Parse args
    {opts, _, _} = OptionParser.parse(args, strict: [limit: :integer])
    limit = Keyword.get(opts, :limit)

    # Start the application
    Mix.Task.run("app.start")

    # Log version of recommended approach
    Mix.shell().info("ℹ️ Running Inquizition scraper using Oban job...")

    # Insert the job
    job_args = if limit, do: %{"limit" => limit}, else: %{}

    case Oban.insert(TriviaAdvisor.Scraping.Oban.InquizitionIndexJob.new(job_args)) do
      {:ok, job} ->
        Mix.shell().info("✅ Successfully scheduled Inquizition scraper job with ID: #{job.id}")
        Mix.shell().info("🔍 Monitor progress in Dashboard: http://localhost:4000/oban")
        # Return success
        :ok

      {:error, changeset} ->
        # Log the error
        Mix.shell().error("❌ Failed to schedule job: #{inspect(changeset.errors)}")
        # Return error code
        exit({:shutdown, 1})
    end
  end
end

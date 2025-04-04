defmodule TriviaAdvisor.Workers.SitemapWorker do
  @moduledoc """
  Oban worker for generating the sitemap on a schedule.
  """

  use Oban.Worker, queue: :default

  alias TriviaAdvisor.Sitemap
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Starting scheduled sitemap generation")

    try do
      Sitemap.generate_and_persist()
      Logger.info("Scheduled sitemap generation completed successfully")
      :ok
    rescue
      error ->
        Logger.error("Sitemap generation failed: #{inspect(error)}")
        {:error, "Sitemap generation failed: #{inspect(error)}"}
    end
  end
end

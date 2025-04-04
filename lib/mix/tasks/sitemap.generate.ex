defmodule Mix.Tasks.Sitemap.Generate do
  use Mix.Task
  require Logger

  @shortdoc "Generates XML sitemap for the TriviaAdvisor website"

  @moduledoc """
  Generates an XML sitemap for the TriviaAdvisor website.

  This task uses the Sitemapper library to generate a sitemap
  for all cities and venues in the database.

  The sitemap will be stored in an S3 bucket specified in the
  application configuration.

  ## Examples

      $ mix sitemap.generate

  """

  @impl Mix.Task
  def run(_args) do
    Logger.info("Starting sitemap generation task")

    # Start the application to make sure the database and other services are ready
    {:ok, _} = Application.ensure_all_started(:trivia_advisor)

    # Generate and persist the sitemap
    case TriviaAdvisor.Sitemap.generate_and_persist() do
      :ok ->
        Logger.info("Sitemap generation task completed successfully")
        :ok

      {:error, error} ->
        Logger.error("Sitemap generation task failed: #{inspect(error)}")
        exit({:shutdown, 1})
    end
  end
end

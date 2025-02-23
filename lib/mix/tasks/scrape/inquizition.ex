defmodule Mix.Tasks.Scrape.Inquizition do
  use Mix.Task
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper

  @shortdoc "Scrapes quiz data from Inquizition"
  @moduledoc """
  Scrapes quiz data from Inquizition website.

  ## Examples

      mix scrape.inquizition

  """

  @impl Mix.Task
  def run(_) do
    Mix.Task.run("app.start")
    Application.ensure_all_started(:httpoison)

    case Scraper.scrape() do
      [] ->
        Mix.shell().error("No venues found")

      venues when is_list(venues) ->
        Mix.shell().info("Found #{length(venues)} venues")
        venues
    end
  end
end

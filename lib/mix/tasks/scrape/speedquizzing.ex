defmodule Mix.Tasks.Scrape.Speedquizzing do
  use Mix.Task
  alias TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.Scraper

  @shortdoc "Run the SpeedQuizzing scraper"

  def run(_) do
    # Start required applications
    [:httpoison, :tzdata]
    |> Enum.each(&Application.ensure_all_started/1)

    # Ensure Ecto repos are started
    Mix.Task.run("app.start")

    # Run the scraper
    Scraper.run()
  end
end

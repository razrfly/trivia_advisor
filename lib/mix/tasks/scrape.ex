defmodule Mix.Tasks.Scrape do
  use Mix.Task

  @shortdoc "Lists available scraping tasks"

  def run(_) do
    Mix.shell().info """
    Available scraping tasks:

      mix scrape.question_one   # Run the QuestionOne scraper
      mix scrape.speedquizzing  # Run the SpeedQuizzing scraper
    """
  end
end

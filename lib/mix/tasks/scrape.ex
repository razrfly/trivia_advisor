defmodule Mix.Tasks.Scrape do
  use Mix.Task

  @shortdoc "Runs the QuestionOne scraper"
  def run(_) do
    # Ensure all dependencies and your app are started
    Application.ensure_all_started(:trivia_advisor)

    IO.puts "Starting QuestionOne scraper..."

    case TriviaAdvisor.Scraping.Scrapers.QuestionOne.run() do
      {:ok, log} ->
        IO.puts "Scrape completed successfully!"
        IO.inspect(log, label: "Scrape Log")

      {:error, error} ->
        IO.puts "Scrape failed!"
        IO.inspect(error, label: "Error")
    end
  end
end

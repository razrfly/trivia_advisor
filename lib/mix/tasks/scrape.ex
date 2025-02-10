defmodule Mix.Tasks.Scrape do
  use Mix.Task

  @shortdoc "Runs the QuestionOne scraper"
  def run(_) do
    # Ensure all dependencies and your app are started
    Application.ensure_all_started(:trivia_advisor)
    Application.ensure_all_started(:httpoison)

    IO.puts "Starting QuestionOne scraper..."

    case TriviaAdvisor.Scraping.Scrapers.QuestionOne.run() do
      {:ok, venues} ->
        IO.puts "\nScrape completed successfully!"
        IO.puts "Found #{length(venues)} total venues"

      {:error, error} ->
        IO.puts "\nScrape failed!"
        IO.puts "Error: #{Exception.message(error)}"
    end
  end
end

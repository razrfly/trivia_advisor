defmodule TriviaAdvisor.Repo.Migrations.DropScrapeLogs do
  use Ecto.Migration

  def change do
    # Drop the scrape_logs table as part of ScrapeLog deprecation
    drop table(:scrape_logs)
  end
end

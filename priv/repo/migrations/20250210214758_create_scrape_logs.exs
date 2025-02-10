defmodule TriviaAdvisor.Repo.Migrations.CreateScrapeLogs do
  use Ecto.Migration

  def change do
    create table(:scrape_logs) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :event_count, :integer, default: 0
      add :success, :boolean, default: false, null: false
      add :metadata, :map, default: "{}"
      add :error, :map, default: "{}"


      timestamps(type: :utc_datetime)
    end

    create index(:scrape_logs, [:source_id])
  end
end

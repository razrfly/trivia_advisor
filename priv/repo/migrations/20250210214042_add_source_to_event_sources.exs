defmodule TriviaAdvisor.Repo.Migrations.AddSourceToEventSources do
  use Ecto.Migration

  def change do
    alter table(:event_sources) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
    end

    create index(:event_sources, [:source_id])
  end
end

defmodule TriviaAdvisor.Repo.Migrations.CreateEventSources do
  use Ecto.Migration

  def change do
    create table(:event_sources) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :source_url, :string, null: false
      add :last_seen_at, :utc_datetime
      add :status, :string, default: "active", null: false
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create index(:event_sources, [:event_id])
  end
end

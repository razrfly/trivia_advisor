defmodule TriviaAdvisor.Repo.Migrations.CreateSources do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :title, :string, null: false
      add :website_url, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sources, [:slug])
    create unique_index(:sources, [:website_url])
  end
end

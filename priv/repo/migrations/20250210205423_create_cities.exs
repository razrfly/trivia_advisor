defmodule TriviaAdvisor.Repo.Migrations.CreateCities do
  use Ecto.Migration

  def change do
    create table(:cities) do
      add :country_id, references(:countries, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cities, [:slug])
    create unique_index(:cities, ["lower(title)"])
    create index(:cities, [:country_id])
  end
end

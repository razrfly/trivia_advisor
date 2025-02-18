defmodule TriviaAdvisor.Repo.Migrations.AddSlugToCountries do
  use Ecto.Migration

  def change do
    alter table(:countries) do
      add :slug, :string, null: false
    end

    create unique_index(:countries, [:slug])
  end
end

defmodule TriviaAdvisor.Repo.Migrations.AddCoordinatesToCities do
  use Ecto.Migration

  def change do
    alter table(:cities) do
      # Same precision and scale as venues
      add :latitude, :decimal, precision: 10, scale: 6
      add :longitude, :decimal, precision: 10, scale: 6
    end

    # Add an index for performance with spatial queries
    create index(:cities, [:latitude, :longitude])
  end
end

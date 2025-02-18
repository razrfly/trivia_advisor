defmodule TriviaAdvisor.Repo.Migrations.ModifyCitiesUniqueConstraint do
  use Ecto.Migration

  def change do
    # Drop the existing indexes
    drop_if_exists index(:cities, ["lower(name)", :country_id], name: :cities_lower_title_index)
    drop_if_exists index(:cities, [:slug], name: :cities_slug_index)

    # Create a new unique index on slug only
    create unique_index(:cities, [:slug], name: :cities_slug_index)
  end
end

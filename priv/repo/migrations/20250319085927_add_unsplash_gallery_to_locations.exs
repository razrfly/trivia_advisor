defmodule TriviaAdvisor.Repo.Migrations.AddUnsplashGalleryToLocations do
  use Ecto.Migration

  def change do
    # Add unsplash_gallery to countries table
    alter table(:countries) do
      add :unsplash_gallery, :jsonb, default: nil
    end

    # Add unsplash_gallery to cities table
    alter table(:cities) do
      add :unsplash_gallery, :jsonb, default: nil
    end

    # Add an index on the unsplash_gallery field for both tables to improve query performance
    # when filtering by unsplash_gallery's existence or properties
    create index(:countries, ["(unsplash_gallery IS NOT NULL)"], name: :countries_unsplash_gallery_exists_index)
    create index(:cities, ["(unsplash_gallery IS NOT NULL)"], name: :cities_unsplash_gallery_exists_index)
  end
end

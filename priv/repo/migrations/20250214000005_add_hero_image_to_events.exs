defmodule TriviaAdvisor.Repo.Migrations.AddHeroImageToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :hero_image_url, :string
      add :hero_image, :string
    end

    # Add an index for faster lookups when filtering by hero_image_url
    create index(:events, [:hero_image_url])
  end
end

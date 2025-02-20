defmodule TriviaAdvisor.Repo.Migrations.AddHeroImageToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :hero_image_url, :string
      add :hero_image, :string
    end
  end
end

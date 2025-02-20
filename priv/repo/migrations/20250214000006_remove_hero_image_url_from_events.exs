defmodule TriviaAdvisor.Repo.Migrations.RemoveHeroImageUrlFromEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      remove :hero_image_url
    end
  end
end

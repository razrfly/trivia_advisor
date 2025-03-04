defmodule TriviaAdvisor.Repo.Migrations.RemoveProfileImageUrlFromPerformers do
  use Ecto.Migration

  def change do
    alter table(:performers) do
      remove :profile_image_url
    end
  end
end

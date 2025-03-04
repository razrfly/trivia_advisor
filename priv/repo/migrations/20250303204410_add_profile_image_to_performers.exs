defmodule TriviaAdvisor.Repo.Migrations.AddProfileImageToPerformers do
  use Ecto.Migration

  def change do
    alter table(:performers) do
      add :profile_image, :map
    end
  end
end

defmodule TriviaAdvisor.Repo.Migrations.AddGooglePlaceImagesToVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :google_place_images, :jsonb, default: "[]"
    end
  end
end

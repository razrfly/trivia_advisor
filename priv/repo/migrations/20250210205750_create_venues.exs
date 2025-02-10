defmodule TriviaAdvisor.Repo.Migrations.CreateVenues do
  use Ecto.Migration

  def change do
    create table(:venues) do
      add :city_id, references(:cities, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :address, :string
      add :postcode, :string
      add :latitude, :decimal, precision: 10, scale: 6, null: false
      add :longitude, :decimal, precision: 10, scale: 6, null: false
      add :place_id, :string
      add :phone, :string
      add :website, :string
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:venues, [:slug])
    create unique_index(:venues, [:place_id])
    create index(:venues, [:city_id])
  end
end

defmodule TriviaAdvisor.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :venue_id, references(:venues, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :day_of_week, :integer, null: false
      add :start_time, :time, null: false
      add :frequency, :integer, default: 0, null: false
      add :entry_fee_cents, :integer, default: 0
      add :description, :text


      timestamps(type: :utc_datetime)
    end

    create index(:events, [:venue_id])
    create unique_index(:events, [:venue_id, :day_of_week, :start_time])
  end
end

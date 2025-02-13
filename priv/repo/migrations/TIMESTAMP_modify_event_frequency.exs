defmodule TriviaAdvisor.Repo.Migrations.ModifyEventFrequency do
  use Ecto.Migration

  def change do
    alter table(:events) do
      modify :frequency, :string
    end
  end
end

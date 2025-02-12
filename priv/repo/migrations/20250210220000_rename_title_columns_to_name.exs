defmodule TriviaAdvisor.Repo.Migrations.RenameTitleColumnsToName do
  use Ecto.Migration

  def change do
    rename table(:cities), :title, to: :name
    rename table(:venues), :title, to: :name
    rename table(:sources), :title, to: :name
    rename table(:events), :title, to: :name
  end
end

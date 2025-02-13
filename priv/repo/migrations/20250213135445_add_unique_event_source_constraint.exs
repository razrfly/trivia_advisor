defmodule TriviaAdvisor.Repo.Migrations.AddUniqueEventSourceConstraint do
  use Ecto.Migration

  def change do
    create unique_index(:event_sources, [:event_id, :source_url])
  end
end

defmodule TriviaAdvisor.Repo.Migrations.AddMetadataToVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :metadata, :jsonb
    end

    # Add GIN index for potential future JSONB queries
    execute(
      "CREATE INDEX venues_metadata_idx ON venues USING GIN (metadata jsonb_path_ops)",
      "DROP INDEX venues_metadata_idx"
    )
  end
end

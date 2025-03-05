defmodule TriviaAdvisor.Repo.Migrations.CleanupDuplicateEventSourcesAndAddUniqueIndex do
  use Ecto.Migration
  require Logger

  def up do
    # Step 1: Find duplicate event sources (same event_id and source_id)
    # and keep only the most recently updated one
    execute """
    WITH ranked_duplicates AS (
      SELECT id, event_id, source_id,
             ROW_NUMBER() OVER (PARTITION BY event_id, source_id ORDER BY updated_at DESC) as rn
      FROM event_sources
    )
    DELETE FROM event_sources
    WHERE id IN (
      SELECT id FROM ranked_duplicates WHERE rn > 1
    );
    """

    # Log how many rows were deleted (using a separate query)
    execute """
    SELECT COUNT(*) as deleted_count FROM (
      WITH ranked_duplicates AS (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY event_id, source_id ORDER BY updated_at DESC) as rn
        FROM event_sources
      )
      SELECT id FROM ranked_duplicates WHERE rn > 1
    ) as deleted_rows;
    """

    # Step 2: Add a unique index to prevent future duplicates
    create unique_index(:event_sources, [:event_id, :source_id], name: :unique_event_source_constraint)
  end

  def down do
    # Drop the unique index if we need to roll back
    drop index(:event_sources, [:event_id, :source_id], name: :unique_event_source_constraint)
  end
end

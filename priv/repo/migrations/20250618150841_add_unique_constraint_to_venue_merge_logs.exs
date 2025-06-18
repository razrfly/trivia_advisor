defmodule TriviaAdvisor.Repo.Migrations.AddUniqueConstraintToVenueMergeLogs do
  use Ecto.Migration

  def up do
    # Add unique constraint to prevent duplicate "not_duplicate" logs for the same venue pair
    # This covers both directions: (venue1, venue2) and (venue2, venue1) using LEAST/GREATEST
    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS venue_merge_logs_unique_action_constraint
    ON venue_merge_logs (
      LEAST(primary_venue_id, secondary_venue_id),
      GREATEST(primary_venue_id, secondary_venue_id),
      action_type
    )
    WHERE action_type = 'not_duplicate'
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS venue_merge_logs_unique_action_constraint"
  end
end

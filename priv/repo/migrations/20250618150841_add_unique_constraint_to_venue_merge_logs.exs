defmodule TriviaAdvisor.Repo.Migrations.AddUniqueConstraintToVenueMergeLogs do
  use Ecto.Migration

  def change do
    # Add unique constraint to prevent duplicate "not_duplicate" logs for the same venue pair
    # This covers both directions: (venue1, venue2) and (venue2, venue1)
    create_if_not_exists unique_index(
      :venue_merge_logs,
      [:primary_venue_id, :secondary_venue_id, :action_type],
      name: :venue_merge_logs_unique_action_constraint,
      where: "action_type = 'not_duplicate'"
    )
  end
end

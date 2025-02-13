defmodule TriviaAdvisor.Repo.Migrations.AddFrequencyToEvents do
  use Ecto.Migration

  def up do
    execute """
    CREATE TYPE event_frequency AS ENUM (
      'weekly',
      'biweekly',
      'monthly',
      'irregular'
    )
    """

    # Drop default and NOT NULL constraint
    execute "ALTER TABLE events ALTER COLUMN frequency DROP DEFAULT"
    execute "ALTER TABLE events ALTER COLUMN frequency DROP NOT NULL"

    # Change the column type
    execute """
    ALTER TABLE events
    ALTER COLUMN frequency TYPE event_frequency
    USING (
      CASE frequency
        WHEN 1 THEN 'weekly'::event_frequency
        WHEN 2 THEN 'biweekly'::event_frequency
        WHEN 3 THEN 'monthly'::event_frequency
        ELSE 'irregular'::event_frequency
      END
    )
    """

    # Add back constraints
    execute "ALTER TABLE events ALTER COLUMN frequency SET DEFAULT 'weekly'::event_frequency"
    execute "ALTER TABLE events ALTER COLUMN frequency SET NOT NULL"
  end

  def down do
    execute "ALTER TABLE events ALTER COLUMN frequency DROP DEFAULT"
    execute "ALTER TABLE events ALTER COLUMN frequency TYPE integer USING CASE frequency::text
      WHEN 'weekly' THEN 1
      WHEN 'biweekly' THEN 2
      WHEN 'monthly' THEN 3
      ELSE 4
    END"
    execute "ALTER TABLE events ALTER COLUMN frequency SET DEFAULT 1"
    execute "DROP TYPE event_frequency"
  end
end

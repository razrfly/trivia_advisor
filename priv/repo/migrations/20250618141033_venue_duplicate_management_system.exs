defmodule TriviaAdvisor.Repo.Migrations.VenueDuplicateManagementSystem do
  use Ecto.Migration

  def up do
    # Add soft delete and merge tracking columns to venues table (if not exist)
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_name = 'venues' AND column_name = 'deleted_at') THEN
        ALTER TABLE venues ADD COLUMN deleted_at timestamp;
      END IF;

      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_name = 'venues' AND column_name = 'deleted_by') THEN
        ALTER TABLE venues ADD COLUMN deleted_by varchar(255);
      END IF;

      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_name = 'venues' AND column_name = 'merged_into_id') THEN
        ALTER TABLE venues ADD COLUMN merged_into_id bigint;
      END IF;
    END $$;
    """

    # Create the audit logs table for tracking merge operations (if not exists)
    execute """
    CREATE TABLE IF NOT EXISTS venue_merge_logs (
      id bigserial primary key,
      action_type varchar(50) NOT NULL,
      primary_venue_id bigint NOT NULL,
      secondary_venue_id bigint NOT NULL,
      metadata jsonb DEFAULT '{}',
      performed_by varchar(255),
      notes text,
      inserted_at timestamp NOT NULL DEFAULT now(),
      updated_at timestamp NOT NULL DEFAULT now()
    );
    """

    # Add indexes for performance (but no foreign key constraints)
    create_if_not_exists index(:venues, [:deleted_at])
    create_if_not_exists index(:venues, [:merged_into_id])
    create_if_not_exists index(:venue_merge_logs, [:primary_venue_id])
    create_if_not_exists index(:venue_merge_logs, [:secondary_venue_id])
    create_if_not_exists index(:venue_merge_logs, [:action_type])

    # Note: View creation moved to post-import to avoid pg_restore conflicts
    # The view will be created by a separate task after data import

    IO.puts """

    ✅ VENUE DUPLICATE MANAGEMENT SYSTEM CREATED!

    📊 INFRASTRUCTURE:
    - Added soft delete columns (deleted_at, deleted_by, merged_into_id) to venues
    - Created venue_merge_logs table for audit trail
    - Added performance indexes
    - Set up structure for potential_duplicate_venues view

    🔧 DESIGN NOTES:
    - No foreign key constraints to avoid production import conflicts
    - View creation deferred to avoid pg_restore conflicts
    - Referential integrity maintained at application level
    - Unique constraints will be added after duplicate resolution

    💡 NEXT STEPS:
    1. Run: mix create_duplicate_view (to create the duplicate detection view)
    2. Use VenueDuplicateDetector and VenueMergeService to resolve duplicates
    3. Once clean, add unique constraints in a follow-up migration
    """
  end

  def down do
    execute "DROP VIEW IF EXISTS potential_duplicate_venues"  # In case it was created manually

    drop index(:venue_merge_logs, [:action_type])
    drop index(:venue_merge_logs, [:secondary_venue_id])
    drop index(:venue_merge_logs, [:primary_venue_id])
    drop index(:venues, [:merged_into_id])
    drop index(:venues, [:deleted_at])

    alter table(:venues) do
      remove :merged_into_id
      remove :deleted_by
      remove :deleted_at
    end

    drop table(:venue_merge_logs)
  end
end

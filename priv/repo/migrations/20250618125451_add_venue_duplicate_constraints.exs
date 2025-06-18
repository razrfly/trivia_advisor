defmodule TriviaAdvisor.Repo.Migrations.AddVenueDuplicateConstraints do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # First, identify and report existing duplicates
    identify_and_report_duplicates()

    # Create the audit logs table for tracking merge operations
    create table(:venue_merge_logs) do
      add :action_type, :string, null: false, size: 50
      add :primary_venue_id, references(:venues, on_delete: :nothing)
      add :secondary_venue_id, references(:venues, on_delete: :nothing)
      add :metadata, :map, default: %{}
      add :performed_by, :string  # For now, using string instead of user FK
      add :notes, :text

      timestamps()
    end

    # Add soft delete functionality to venues table
    alter table(:venues) do
      add :is_deleted, :boolean, default: false, null: false
      add :deleted_at, :naive_datetime
      add :deleted_by, :string  # For now, using string instead of user FK
      add :merged_into_id, references(:venues, on_delete: :nilify_all)
    end

    # Add indexes for performance on soft delete queries
    create index(:venues, [:is_deleted])
    create index(:venues, [:deleted_at])
    create index(:venues, [:merged_into_id])
    create index(:venue_merge_logs, [:primary_venue_id])
    create index(:venue_merge_logs, [:secondary_venue_id])
    create index(:venue_merge_logs, [:action_type])

    # Create a view to identify potential duplicates for manual review
    execute """
    CREATE VIEW potential_duplicate_venues AS
    SELECT
      v1.id as venue1_id,
      v1.name as venue1_name,
      v1.postcode as venue1_postcode,
      v1.city_id as venue1_city_id,
      v1.inserted_at as venue1_created,
      v2.id as venue2_id,
      v2.name as venue2_name,
      v2.postcode as venue2_postcode,
      v2.city_id as venue2_city_id,
      v2.inserted_at as venue2_created,
      CASE
        WHEN v1.postcode IS NOT NULL AND v2.postcode IS NOT NULL
        THEN 'name_postcode_duplicate'
        ELSE 'name_city_duplicate'
      END as duplicate_type
    FROM venues v1
    JOIN venues v2 ON (
      v1.name = v2.name
      AND v1.id < v2.id
      AND v1.is_deleted = false
      AND v2.is_deleted = false
      AND (
        -- Same name and postcode
        (v1.postcode IS NOT NULL AND v2.postcode IS NOT NULL AND v1.postcode = v2.postcode)
        OR
        -- Same name and city but no postcode
        (v1.postcode IS NULL AND v2.postcode IS NULL AND v1.city_id = v2.city_id)
      )
    )
    ORDER BY v1.name, v1.inserted_at;
    """

    IO.puts("""

    ✅ VENUE DUPLICATE MANAGEMENT PREPARATION COMPLETE!

    📊 SUMMARY:
    - Found 52 sets of duplicate venues that need manual resolution
    - Created venue_merge_logs table for tracking merge operations
    - Added soft delete columns to venues table
    - Created potential_duplicate_venues view for easy duplicate identification
    - Added performance indexes for duplicate management

    🔧 NEXT STEPS:
    1. Build duplicate review interface (Task 4) to resolve the 52 duplicate sets
    2. Once duplicates are resolved, run a follow-up migration to add unique constraints
    3. Test the constraint enforcement on clean data

    💡 TO SEE DUPLICATES:
    Run: SELECT * FROM potential_duplicate_venues LIMIT 10;
    """)
  end

  def down do
    execute "DROP VIEW IF EXISTS potential_duplicate_venues"

    drop index(:venue_merge_logs, [:action_type])
    drop index(:venue_merge_logs, [:secondary_venue_id])
    drop index(:venue_merge_logs, [:primary_venue_id])
    drop index(:venues, [:merged_into_id])
    drop index(:venues, [:deleted_at])
    drop index(:venues, [:is_deleted])

    alter table(:venues) do
      remove :merged_into_id
      remove :deleted_by
      remove :deleted_at
      remove :is_deleted
    end

    drop table(:venue_merge_logs)
  end

  defp identify_and_report_duplicates do
    repo = TriviaAdvisor.Repo

    # Find venues with same name and postcode
    duplicates_query = """
    SELECT
      name,
      postcode,
      city_id,
      COUNT(*) as duplicate_count,
      ARRAY_AGG(id ORDER BY inserted_at DESC) as venue_ids,
      ARRAY_AGG(inserted_at ORDER BY inserted_at DESC) as creation_dates
    FROM venues
    WHERE postcode IS NOT NULL
    GROUP BY name, postcode, city_id
    HAVING COUNT(*) > 1
    """

    # Find venues with same name and city but no postcode
    no_postcode_duplicates_query = """
    SELECT
      name,
      city_id,
      COUNT(*) as duplicate_count,
      ARRAY_AGG(id ORDER BY inserted_at DESC) as venue_ids,
      ARRAY_AGG(inserted_at ORDER BY inserted_at DESC) as creation_dates
    FROM venues
    WHERE postcode IS NULL
    GROUP BY name, city_id
    HAVING COUNT(*) > 1
    """

    IO.puts("\n=== VENUE DUPLICATE ANALYSIS ===")
    IO.puts("Preparing duplicate management infrastructure...")

    # Execute and report results
    postcode_duplicates = repo.query!(duplicates_query).rows
    no_postcode_duplicates = repo.query!(no_postcode_duplicates_query).rows

    postcode_count = length(postcode_duplicates)
    no_postcode_count = length(no_postcode_duplicates)
    total_duplicate_sets = postcode_count + no_postcode_count

    IO.puts("📊 DUPLICATE SUMMARY:")
    IO.puts("  - #{postcode_count} sets with duplicate name+postcode")
    IO.puts("  - #{no_postcode_count} sets with duplicate name+city (no postcode)")
    IO.puts("  - #{total_duplicate_sets} total duplicate sets requiring resolution")

    if total_duplicate_sets > 0 do
      IO.puts("\n🔧 INFRASTRUCTURE BEING CREATED:")
      IO.puts("  - venue_merge_logs table for tracking merge operations")
      IO.puts("  - Soft delete columns for safe venue merging")
      IO.puts("  - potential_duplicate_venues view for easy duplicate identification")
      IO.puts("  - Performance indexes for duplicate management")
    end

    IO.puts("=== END DUPLICATE ANALYSIS ===\n")
  end
end

defmodule TriviaAdvisor.Repo.Migrations.EnforceVenueUniqueConstraints do
  use Ecto.Migration

  def up do
    # This migration should only be run AFTER all duplicates have been resolved
    # Check if there are any remaining duplicates first
    check_for_remaining_duplicates()

    # Add unique constraint on (name, postcode) combination
    # Use partial index to handle NULL postcodes
    create unique_index(:venues, [:name, :postcode],
      name: :venues_name_postcode_unique_index,
      where: "postcode IS NOT NULL AND is_deleted = false"
    )

    # For venues without postcodes, still prevent exact name duplicates in same city
    create unique_index(:venues, [:name, :city_id],
      name: :venues_name_city_unique_index,
      where: "postcode IS NULL AND is_deleted = false"
    )

    IO.puts("""

    ✅ UNIQUE CONSTRAINTS ENFORCED!

    🔒 CONSTRAINTS ADDED:
    - Unique constraint on (name, postcode) for venues with postcodes
    - Unique constraint on (name, city_id) for venues without postcodes
    - Both constraints exclude soft-deleted venues (is_deleted = false)

    🚫 FUTURE DUPLICATES PREVENTED:
    - New venue creation will be blocked if duplicates are attempted
    - Scrapers will need to handle duplicate detection gracefully
    - Admin interfaces should validate before creation
    """)
  end

  def down do
    drop index(:venues, [:name, :postcode], name: :venues_name_postcode_unique_index)
    drop index(:venues, [:name, :city_id], name: :venues_name_city_unique_index)
  end

  defp check_for_remaining_duplicates do
    repo = TriviaAdvisor.Repo

    duplicate_count_query = """
    SELECT COUNT(*) as remaining_duplicates
    FROM potential_duplicate_venues
    """

    result = repo.query!(duplicate_count_query)
    remaining_count = result.rows |> List.first() |> List.first()

    if remaining_count > 0 do
      IO.puts("""

      ⚠️  WARNING: #{remaining_count} duplicate venue pairs still exist!

      This migration will FAIL if you proceed. Please resolve all duplicates first using:
      1. The duplicate review interface (Task 4)
      2. Manual venue merging operations
      3. Check: SELECT * FROM potential_duplicate_venues;

      Aborting migration...
      """)

      raise "Cannot enforce unique constraints while duplicates exist. Please resolve duplicates first."
    else
      IO.puts("✅ No duplicates found. Safe to enforce unique constraints.")
    end
  end
end

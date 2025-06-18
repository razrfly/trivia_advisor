defmodule TriviaAdvisor.Repo.Migrations.IntegrateEctoSoftDelete do
  use Ecto.Migration

  def up do
    # First drop the view that depends on the is_deleted column
    execute """
    DROP VIEW IF EXISTS potential_duplicate_venues;
    """

    # Remove the is_deleted column since ecto_soft_delete only uses deleted_at
    alter table(:venues) do
      remove :is_deleted
    end

    # Update the potential_duplicate_venues view to use ecto_soft_delete convention

    execute """
    CREATE VIEW potential_duplicate_venues AS
    WITH duplicate_groups AS (
      SELECT
        venues.name,
        COALESCE(venues.postcode, city.name) as location_key,
        COUNT(*) as duplicate_count,
        ARRAY_AGG(venues.id ORDER BY venues.id) as venue_ids
      FROM venues
      LEFT JOIN cities city ON venues.city_id = city.id
      WHERE venues.deleted_at IS NULL  -- Use ecto_soft_delete convention
      GROUP BY venues.name, COALESCE(venues.postcode, city.name)
      HAVING COUNT(*) > 1
    )
    SELECT
      dg.name,
      dg.location_key,
      dg.duplicate_count,
      dg.venue_ids,
      -- Detailed venue information for each duplicate
      (
        SELECT JSON_AGG(
          JSON_BUILD_OBJECT(
            'id', v.id,
            'name', v.name,
            'address', v.address,
            'postcode', v.postcode,
            'city_name', c.name,
            'city_id', v.city_id,
            'latitude', v.latitude,
            'longitude', v.longitude,
            'place_id', v.place_id,
            'inserted_at', v.inserted_at,
            'updated_at', v.updated_at
          ) ORDER BY v.id
        )
        FROM venues v
        LEFT JOIN cities c ON v.city_id = c.id
        WHERE v.id = ANY(dg.venue_ids)
          AND v.deleted_at IS NULL  -- Use ecto_soft_delete convention
      ) as venue_details
    FROM duplicate_groups dg;
    """

    # Note: deleted_at index already exists from previous migration
  end

  def down do
    # Add back the is_deleted column
    alter table(:venues) do
      add :is_deleted, :boolean, default: false, null: false
    end

    # Restore the original view
    execute """
    DROP VIEW IF EXISTS potential_duplicate_venues;
    """

    execute """
    CREATE VIEW potential_duplicate_venues AS
    WITH duplicate_groups AS (
      SELECT
        venues.name,
        COALESCE(venues.postcode, city.name) as location_key,
        COUNT(*) as duplicate_count,
        ARRAY_AGG(venues.id ORDER BY venues.id) as venue_ids
      FROM venues
      LEFT JOIN cities city ON venues.city_id = city.id
      WHERE venues.is_deleted = false
      GROUP BY venues.name, COALESCE(venues.postcode, city.name)
      HAVING COUNT(*) > 1
    )
    SELECT
      dg.name,
      dg.location_key,
      dg.duplicate_count,
      dg.venue_ids,
      -- Detailed venue information for each duplicate
      (
        SELECT JSON_AGG(
          JSON_BUILD_OBJECT(
            'id', v.id,
            'name', v.name,
            'address', v.address,
            'postcode', v.postcode,
            'city_name', c.name,
            'city_id', v.city_id,
            'latitude', v.latitude,
            'longitude', v.longitude,
            'place_id', v.place_id,
            'inserted_at', v.inserted_at,
            'updated_at', v.updated_at
          ) ORDER BY v.id
        )
        FROM venues v
        LEFT JOIN cities c ON v.city_id = c.id
        WHERE v.id = ANY(dg.venue_ids)
          AND v.is_deleted = false
      ) as venue_details
    FROM duplicate_groups dg;
    """

    # Note: deleted_at index will remain for original migration compatibility
  end
end

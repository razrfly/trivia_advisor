defmodule Mix.Tasks.CreateDuplicateView do
  @moduledoc """
  Creates the potential_duplicate_venues view after data import.

  This task creates the view that was intentionally omitted from the migration
  to avoid conflicts with pg_restore during production data imports.

  ## Examples

      mix create_duplicate_view

  """
  use Mix.Task
  require Logger

  @shortdoc "Creates the potential_duplicate_venues view"

  @impl Mix.Task
  def run(_args) do
    # Start the application to ensure the repo is available
    Mix.Task.run("app.start")

    Logger.info("Creating potential_duplicate_venues view...")

    sql = """
    CREATE OR REPLACE VIEW potential_duplicate_venues AS
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
      AND v1.deleted_at IS NULL
      AND v2.deleted_at IS NULL
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

    try do
      TriviaAdvisor.Repo.query!(sql)
      Logger.info("✅ potential_duplicate_venues view created successfully")

      # Query and display duplicate count
      result = TriviaAdvisor.Repo.query!("SELECT COUNT(*) as count FROM potential_duplicate_venues")
      count = result.rows |> List.first() |> List.first()

      Logger.info("📊 Found #{count} duplicate venue pairs")

      if count > 0 do
        Logger.info("💡 Run: SELECT * FROM potential_duplicate_venues LIMIT 10; to see examples")
      end

    rescue
      e ->
        Logger.error("❌ Failed to create view: #{inspect(e)}")
        exit({:shutdown, 1})
    end
  end
end

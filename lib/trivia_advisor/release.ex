defmodule TriviaAdvisor.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :trivia_advisor

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    # Create duplicate detection view after migrations
    create_duplicate_view()

    # Skip fuzzy duplicates during migration - they can be processed later
    # This prevents deployment timeouts and allows the app to start quickly
    IO.puts("⏭️  Skipping fuzzy duplicate processing during migration")
    IO.puts("   Run 'mix process_fuzzy_duplicates' after deployment completes")
    IO.puts("   Or use the admin interface to process them manually")

    # Run seeds after migrations
    seed()
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo ->
        seed_path = Application.app_dir(@app, "priv/repo/seeds.exs")
        if File.exists?(seed_path) do
          Code.eval_file(seed_path)
        end
      end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_duplicate_view do
    load_app()

    IO.puts("Creating potential_duplicate_venues view...")

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
      lower(trim(v1.name)) = lower(trim(v2.name))
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
      for repo <- repos() do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn repo ->
          repo.query!(sql)
        end)
      end

      IO.puts("✅ potential_duplicate_venues view created successfully")

      # Query and display duplicate count for the primary repo
      primary_repo = hd(repos())
      result = primary_repo.query!("SELECT COUNT(*) as count FROM potential_duplicate_venues")
      count = result.rows |> List.first() |> List.first()

      IO.puts("📊 Found #{count} duplicate venue pairs")

      if count > 0 do
        IO.puts("💡 Visit /admin/venues/duplicates to review and manage duplicates")
      end

    rescue
      e ->
        IO.puts("❌ Failed to create view: #{inspect(e)}")
        # Don't exit on error in production - log and continue
    end
  end

  @doc """
  Process all venues to find fuzzy duplicates using AI detection.
  This replaces the simple SQL view with sophisticated duplicate detection.
  """
  def process_fuzzy_duplicates do
    load_app()

    IO.puts("🤖 Processing fuzzy duplicates with AI detection...")

    try do
      alias TriviaAdvisor.Services.FuzzyDuplicateProcessor

      # Clear existing records and reprocess
      options = [
        clear_existing: true,
        min_confidence: 0.70,
        batch_size: 100
      ]

      result = FuzzyDuplicateProcessor.process_all_venues(options)

      case result do
        {:ok, stats} ->
          IO.puts("✅ Fuzzy duplicate processing completed successfully")
          IO.puts("📊 Processed #{stats.processed} venues")
          IO.puts("📊 Found #{stats.duplicates_found} potential duplicates")
          IO.puts("📊 Stored #{stats.duplicates_stored} high-confidence pairs")

          # Show statistics
          final_stats = FuzzyDuplicateProcessor.get_statistics()
          IO.puts("\n📈 FINAL STATISTICS:")
          IO.puts("   Total pairs: #{final_stats[:total]}")
          IO.puts("   High confidence (90%+): #{final_stats[:high_confidence]}")
          IO.puts("   Medium confidence (75-89%): #{final_stats[:medium_confidence]}")
          IO.puts("   Low confidence (<75%): #{final_stats[:low_confidence]}")
          if final_stats[:avg_confidence] do
            IO.puts("   Average confidence: #{Float.round(final_stats[:avg_confidence], 1)}%")
          end

          IO.puts("\n💡 Visit /admin/venues/duplicates to review and manage fuzzy duplicates")
          {:ok, stats}

        error ->
          IO.puts("❌ Error processing fuzzy duplicates: #{inspect(error)}")
          {:error, error}
      end
    rescue
      e ->
        IO.puts("❌ Error processing fuzzy duplicates: #{inspect(e)}")
        {:error, e}
    end
  end

  def package_sentry_source do
    if Mix.env() == :prod do
      load_app()
      Mix.Tasks.Sentry.PackageSourceCode.run([])
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end

defmodule TriviaAdvisor.Repo.Migrations.CreateFuzzyDuplicatesTable do
  use Ecto.Migration

  def up do
    create table(:venue_fuzzy_duplicates) do
      add :venue1_id, :bigint, null: false
      add :venue2_id, :bigint, null: false
      add :confidence_score, :float, null: false
      add :name_similarity, :float, null: false
      add :location_similarity, :float, null: false
      add :match_criteria, {:array, :string}, default: []
      add :status, :string, default: "pending"  # pending, reviewed, merged, rejected
      add :reviewed_at, :utc_datetime
      add :reviewed_by, :string

      timestamps(type: :utc_datetime)
    end

    # Ensure venue1_id < venue2_id to avoid duplicate pairs
    create unique_index(:venue_fuzzy_duplicates, [:venue1_id, :venue2_id])

    # Indexes for performance
    create index(:venue_fuzzy_duplicates, [:confidence_score])
    create index(:venue_fuzzy_duplicates, [:status])
    create index(:venue_fuzzy_duplicates, [:venue1_id])
    create index(:venue_fuzzy_duplicates, [:venue2_id])

    IO.puts """

    ✅ FUZZY DUPLICATES TABLE CREATED!

    📊 FEATURES:
    - Stores venue pairs with confidence scores
    - Tracks name and location similarity separately
    - Records match criteria for transparency
    - Supports review status tracking
    - Unique constraint prevents duplicate pairs
    - Optimized indexes for performance

    💡 NEXT STEPS:
    1. Run the fuzzy duplicate detection batch process
    2. Update admin interface to use confidence scores
    3. Add filtering by confidence levels
    """
  end

  def down do
    drop table(:venue_fuzzy_duplicates)
  end
end

defmodule TriviaAdvisor.Locations.VenueFuzzyDuplicate do
  @moduledoc """
  Schema for storing fuzzy duplicate venue pairs with confidence scores.

  This table stores pairs of venues that have been identified as potential duplicates
  by the VenueDuplicateDetector service, along with their confidence scores and
  detailed similarity metrics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TriviaAdvisor.Locations.Venue

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "venue_fuzzy_duplicates" do
    field :venue1_id, :integer
    field :venue2_id, :integer
    field :confidence_score, :float
    field :name_similarity, :float
    field :location_similarity, :float
    field :match_criteria, {:array, :string}, default: []
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime
    field :reviewed_by, :string

    # Virtual fields for preloaded venues
    belongs_to :venue1, Venue, foreign_key: :venue1_id, define_field: false
    belongs_to :venue2, Venue, foreign_key: :venue2_id, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(fuzzy_duplicate, attrs) do
    fuzzy_duplicate
    |> cast(attrs, [
      :venue1_id, :venue2_id, :confidence_score, :name_similarity,
      :location_similarity, :match_criteria, :status, :reviewed_at, :reviewed_by
    ])
    |> validate_required([:venue1_id, :venue2_id, :confidence_score, :name_similarity, :location_similarity])
    |> validate_inclusion(:status, ["pending", "reviewed", "merged", "rejected"])
    |> validate_number(:confidence_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:name_similarity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:location_similarity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> ensure_venue_order()
    |> unique_constraint([:venue1_id, :venue2_id])
  end

  # Ensure venue1_id < venue2_id to avoid duplicate pairs
  defp ensure_venue_order(changeset) do
    venue1_id = get_field(changeset, :venue1_id)
    venue2_id = get_field(changeset, :venue2_id)

    if venue1_id && venue2_id && venue1_id > venue2_id do
      changeset
      |> put_change(:venue1_id, venue2_id)
      |> put_change(:venue2_id, venue1_id)
    else
      changeset
    end
  end

  @doc """
  Returns a confidence level atom based on the confidence score.

  ## Examples

      iex> confidence_level(0.95)
      :high

      iex> confidence_level(0.80)
      :medium

      iex> confidence_level(0.60)
      :low
  """
  def confidence_level(score) when is_float(score) do
    cond do
      score >= 0.90 -> :high
      score >= 0.75 -> :medium
      true -> :low
    end
  end

  @doc """
  Returns a human-readable confidence description.
  """
  def confidence_description(:high), do: "High Confidence (90%+)"
  def confidence_description(:medium), do: "Medium Confidence (75-89%)"
  def confidence_description(:low), do: "Low Confidence (<75%)"

  def confidence_description(score) when is_float(score) do
    score |> confidence_level() |> confidence_description()
  end
end

defmodule TriviaAdvisor.Events.VenueMergeLog do
  @moduledoc """
  Schema for tracking venue merge operations and audit trail.

  Each merge operation creates a log entry that tracks:
  - Which venues were merged (primary and secondary)
  - What action was performed
  - Metadata about the merge (conflicting data, resolution choices)
  - Who performed the merge
  - When it was performed
  - Optional notes
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Locations.Venue

  schema "venue_merge_logs" do
    field :action_type, :string
    field :metadata, :map, default: %{}
    field :performed_by, :string
    field :notes, :string

    belongs_to :primary_venue, Venue
    belongs_to :secondary_venue, Venue

    timestamps(type: :utc_datetime)
  end

  @valid_actions ~w(merge preview rollback)

  @doc false
  def changeset(venue_merge_log, attrs) do
    venue_merge_log
    |> cast(attrs, [:action_type, :primary_venue_id, :secondary_venue_id, :metadata, :performed_by, :notes])
    |> validate_required([:action_type, :primary_venue_id, :secondary_venue_id])
    |> validate_inclusion(:action_type, @valid_actions)
    |> validate_length(:action_type, max: 50)
    |> validate_different_venues()
    |> foreign_key_constraint(:primary_venue_id)
    |> foreign_key_constraint(:secondary_venue_id)
  end

  defp validate_different_venues(changeset) do
    primary_id = get_field(changeset, :primary_venue_id)
    secondary_id = get_field(changeset, :secondary_venue_id)

    if primary_id && secondary_id && primary_id == secondary_id do
      add_error(changeset, :secondary_venue_id, "cannot be the same as primary venue")
    else
      changeset
    end
  end
end

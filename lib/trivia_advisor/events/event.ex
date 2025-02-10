defmodule TriviaAdvisor.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :title, :string
    field :day_of_week, :integer
    field :start_time, :time
    field :frequency, :integer
    field :entry_fee_cents, :integer
    field :description, :string

    belongs_to :venue, TriviaAdvisor.Locations.Venue
    has_many :event_sources, TriviaAdvisor.Events.EventSource, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :day_of_week, :start_time, :frequency, :entry_fee_cents, :description, :venue_id])
    |> validate_required([:day_of_week, :start_time, :frequency, :venue_id])
  end
end

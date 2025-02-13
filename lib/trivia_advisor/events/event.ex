defmodule TriviaAdvisor.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @frequencies ~w(weekly biweekly monthly irregular)a

  schema "events" do
    field :name, :string
    field :day_of_week, :integer
    field :start_time, :time
    field :frequency, Ecto.Enum, values: @frequencies, default: :weekly
    field :entry_fee_cents, :integer
    field :description, :string

    belongs_to :venue, TriviaAdvisor.Locations.Venue
    has_many :event_sources, TriviaAdvisor.Events.EventSource, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :day_of_week, :start_time, :frequency, :entry_fee_cents, :description, :venue_id])
    |> validate_required([:day_of_week, :start_time, :frequency, :venue_id])
  end

  @doc """
  Parses frequency text into the correct enum value.
  """
  def parse_frequency(text) when is_binary(text) do
    text = String.trim(text) |> String.downcase()
    cond do
      text == "" -> :irregular
      Regex.match?(~r/\b(every\s+2\s+weeks?|bi-?weekly|fortnightly)\b/, text) -> :biweekly
      Regex.match?(~r/\b(every\s+week|weekly|each\s+week)\b/, text) -> :weekly
      Regex.match?(~r/\b(every\s+month|monthly)\b/, text) -> :monthly
      true -> :irregular
    end
  end
  def parse_frequency(_), do: :irregular
end

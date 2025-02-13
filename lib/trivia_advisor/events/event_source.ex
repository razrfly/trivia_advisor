defmodule TriviaAdvisor.Events.EventSource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_sources" do
    field :source_url, :string
    field :last_seen_at, :utc_datetime
    field :status, :string, default: "active"
    field :metadata, :map

    belongs_to :event, TriviaAdvisor.Events.Event
    belongs_to :source, TriviaAdvisor.Scraping.Source

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event_source, attrs) do
    event_source
    |> cast(attrs, [:status, :metadata, :source_url, :last_seen_at, :event_id, :source_id])
    |> validate_required([:source_url, :last_seen_at, :event_id, :source_id])
    |> unique_constraint([:event_id, :source_url], name: "event_sources_event_id_source_url_index")
  end
end

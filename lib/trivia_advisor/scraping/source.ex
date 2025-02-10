defmodule TriviaAdvisor.Scraping.Source do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sources" do
    field :title, :string
    field :website_url, :string
    field :slug, :string

    has_many :event_sources, TriviaAdvisor.Events.EventSource, on_delete: :delete_all
    has_many :scrape_logs, TriviaAdvisor.Scraping.ScrapeLog, on_delete: :delete_all
    has_many :events, through: [:event_sources, :event]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:title, :website_url, :slug])
    |> validate_required([:title, :website_url, :slug])
    |> unique_constraint(:slug)
    |> unique_constraint(:website_url)
  end
end

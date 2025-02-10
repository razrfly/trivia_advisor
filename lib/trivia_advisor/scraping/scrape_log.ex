defmodule TriviaAdvisor.Scraping.ScrapeLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "scrape_logs" do
    field :event_count, :integer
    field :success, :boolean, default: false
    field :error, :map
    field :metadata, :map

    belongs_to :source, TriviaAdvisor.Scraping.Source

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(scrape_log, attrs) do
    scrape_log
    |> cast(attrs, [:event_count, :success, :metadata, :error, :source_id])
    |> validate_required([:source_id])
  end
end

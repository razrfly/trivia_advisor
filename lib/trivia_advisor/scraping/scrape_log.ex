defmodule TriviaAdvisor.Scraping.ScrapeLog do
  use Ecto.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Repo

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

  def create_log(source) do
    %__MODULE__{}
    |> changeset(%{
      source_id: source.id,
      success: false,
      metadata: %{
        started_at: DateTime.utc_now(),
        scraper_version: "1.0.0"
      }
    })
    |> Repo.insert()
  end

  def update_log(log, attrs) do
    attrs = if attrs[:metadata] do
      new_metadata = Map.merge(log.metadata || %{}, attrs.metadata)
      %{attrs | metadata: new_metadata}
    else
      attrs
    end

    log
    |> changeset(attrs)
    |> Repo.update()
  end

  def log_error(log, error) do
    update_log(log, %{
      success: false,
      error: %{
        message: Exception.message(error),
        type: inspect(Exception.normalize(:error, error))
      }
    })
  end
end

defmodule TriviaAdvisor.Scraping.Source do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sources" do
    field :name, :string
    field :slug, :string
    field :website_url, :string

    has_many :event_sources, TriviaAdvisor.Events.EventSource, on_delete: :delete_all
    has_many :events, through: [:event_sources, :event]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :slug, :website_url])
    |> validate_required([:name])
    |> validate_format(:website_url, ~r/^https?:\/\/.*$/, message: "must start with http:// or https://")
    |> put_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:website_url)
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""
        slug = String.downcase(name) |> String.replace(" ", "-")
        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end

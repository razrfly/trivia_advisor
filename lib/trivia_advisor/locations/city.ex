defmodule TriviaAdvisor.Locations.City do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cities" do
    field :title, :string
    field :slug, :string

    belongs_to :country, TriviaAdvisor.Locations.Country
    has_many :venues, TriviaAdvisor.Locations.Venue

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [:title, :country_id, :slug])
    |> validate_required([:title, :country_id])
    |> put_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:title, name: :cities_lower_title_index)
    |> foreign_key_constraint(:country_id)
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        title = get_field(changeset, :title) || ""
        slug = String.downcase(title) |> String.replace(" ", "-")
        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end

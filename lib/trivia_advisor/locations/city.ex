defmodule TriviaAdvisor.Locations.City do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cities" do
    field :name, :string
    field :slug, :string

    belongs_to :country, TriviaAdvisor.Locations.Country
    has_many :venues, TriviaAdvisor.Locations.Venue

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [:name, :country_id])
    |> validate_required([:name, :country_id])
    |> put_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:name, name: :cities_lower_title_index)
    |> foreign_key_constraint(:country_id)
  end

  defp put_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, Slug.slugify(name))
    end
  end
end

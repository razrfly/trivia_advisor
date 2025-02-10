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
    |> cast(attrs, [:title, :slug, :country_id])
    |> validate_required([:title, :slug, :country_id])
    |> unique_constraint(:slug)
  end
end

defmodule TriviaAdvisor.Locations.Venue do
  use Ecto.Schema
  import Ecto.Changeset

  schema "venues" do
    field :address, :string
    field :title, :string
    field :postcode, :string
    field :latitude, :decimal
    field :longitude, :decimal
    field :place_id, :string
    field :phone, :string
    field :website, :string
    field :slug, :string

    belongs_to :city, TriviaAdvisor.Locations.City

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:title, :address, :postcode, :latitude, :longitude, :place_id, :phone, :website, :slug, :city_id])
    |> validate_required([:title, :address, :postcode, :latitude, :longitude, :slug, :city_id])
    |> unique_constraint(:slug)
    |> unique_constraint(:place_id)
  end
end

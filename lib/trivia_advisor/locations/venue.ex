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
    has_many :events, TriviaAdvisor.Events.Event

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:city_id, :title, :address, :postcode, :latitude, :longitude,
                    :place_id, :phone, :website, :slug])
    |> validate_required([:city_id, :title, :latitude, :longitude])
    |> put_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:place_id)
    |> foreign_key_constraint(:city_id)
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

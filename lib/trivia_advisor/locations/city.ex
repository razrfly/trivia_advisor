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
    |> cast(attrs, [:name, :country_id, :slug])
    |> validate_required([:name, :country_id, :slug])
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:country_id)
  end

  # Remove or comment out this function since we're handling slug generation in VenueStore
  # defp maybe_generate_slug(%{changes: %{slug: _}} = changeset), do: changeset
  # defp maybe_generate_slug(changeset) do
  #   if get_change(changeset, :name) do
  #     put_change(changeset, :slug, generate_slug(get_change(changeset, :name)))
  #   else
  #     changeset
  #   end
  # end
end

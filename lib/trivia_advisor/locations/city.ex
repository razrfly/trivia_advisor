defmodule TriviaAdvisor.Locations.City do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{Country, Venue}

  schema "cities" do
    field :name, :string
    field :slug, :string
    field :latitude, :decimal
    field :longitude, :decimal
    field :unsplash_gallery, :map

    belongs_to :country, Country
    has_many :venues, Venue

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [:name, :country_id, :latitude, :longitude, :unsplash_gallery])
    |> validate_required([:name, :country_id])
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> foreign_key_constraint(:country_id)
    |> generate_slug()
    |> unique_constraint(:slug)
  end

  defp generate_slug(%Ecto.Changeset{valid?: true, changes: %{name: name}} = changeset) do
    base_slug = Slug.slugify(name)

    case check_slug_conflict(base_slug, get_field(changeset, :country_id)) do
      true ->
        # Conflict exists, append country code
        country_code = Repo.get(Country, get_field(changeset, :country_id)).code
        put_change(changeset, :slug, "#{base_slug}-#{String.downcase(country_code)}")
      false ->
        # No conflict, use base slug
        put_change(changeset, :slug, base_slug)
    end
  end

  defp generate_slug(changeset), do: changeset

  defp check_slug_conflict(slug, country_id) do
    query = from c in __MODULE__,
            where: c.slug == ^slug and c.country_id != ^country_id

    Repo.exists?(query)
  end

  @doc """
  Helper function to get coordinates as a tuple
  Returns nil if coordinates are not set
  """
  def coordinates(%__MODULE__{latitude: lat, longitude: lng})
    when not is_nil(lat) and not is_nil(lng) do
    {Decimal.to_float(lat), Decimal.to_float(lng)}
  end
  def coordinates(_), do: nil
end

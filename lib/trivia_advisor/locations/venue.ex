defmodule TriviaAdvisor.Locations.Venue do
  use Ecto.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Repo

  schema "venues" do
    field :name, :string
    field :slug, :string
    field :address, :string
    field :postcode, :string
    field :latitude, :decimal
    field :longitude, :decimal
    field :place_id, :string
    field :phone, :string
    field :website, :string
    field :metadata, :map

    belongs_to :city, TriviaAdvisor.Locations.City
    has_many :events, TriviaAdvisor.Events.Event

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :address, :latitude, :longitude, :place_id, :phone, :website, :city_id, :postcode, :metadata])
    |> validate_required([:name, :address, :latitude, :longitude, :city_id])
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> put_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:place_id)
    |> foreign_key_constraint(:city_id)
  end

  defp put_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name ->
        # Get city and postcode from changeset if available
        city_name = get_in(get_change(changeset, :metadata) || %{}, ["city", "name"])
        postcode = get_change(changeset, :postcode)

        # Try different slug combinations
        slug = cond do
          # Try name only
          !slug_exists?(Slug.slugify(name)) ->
            Slug.slugify(name)

          # Try name + city
          city_name && !slug_exists?(Slug.slugify("#{name} #{city_name}")) ->
            Slug.slugify("#{name} #{city_name}")

          # Try name + city + postcode
          city_name && postcode && !slug_exists?(Slug.slugify("#{name} #{city_name} #{postcode}")) ->
            Slug.slugify("#{name} #{city_name} #{postcode}")

          # Fallback: name + timestamp
          true ->
            Slug.slugify("#{name} #{System.system_time(:second)}")
        end

        put_change(changeset, :slug, slug)
    end
  end

  defp slug_exists?(slug) do
    case Repo.get_by(__MODULE__, slug: slug) do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Helper function to get coordinates as a tuple
  """
  def coordinates(%__MODULE__{latitude: lat, longitude: lng})
    when not is_nil(lat) and not is_nil(lng) do
    {Decimal.to_float(lat), Decimal.to_float(lng)}
  end
  def coordinates(_), do: nil
end

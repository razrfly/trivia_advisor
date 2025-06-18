defmodule TriviaAdvisor.Locations.Venue do
  use Ecto.Schema
  import Ecto.SoftDelete.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Services.GooglePlaceImageStore

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
    field :facebook, :string
    field :instagram, :string
    field :metadata, :map
    field :google_place_images, {:array, :map}, default: []

    # Soft delete and merge tracking fields
    field :deleted_by, :string
    field :merged_into_id, :integer

    belongs_to :city, TriviaAdvisor.Locations.City
    has_many :events, TriviaAdvisor.Events.Event

    timestamps(type: :utc_datetime)
    soft_delete_schema()
  end

  @url_regex ~r/^https?:\/\/[^\s\/$.?#].[^\s]*$/i

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :address, :latitude, :longitude, :place_id, :phone, :website, :facebook, :instagram, :city_id, :postcode, :metadata, :google_place_images])
    |> validate_required([:name, :address, :latitude, :longitude, :city_id])
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> cleanup_url(:website)
    |> cleanup_url(:facebook)
    |> cleanup_url(:instagram)
    |> handle_google_place_images_change(venue)
    |> put_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:place_id)
    |> foreign_key_constraint(:city_id)
  end

  @doc """
  Changeset for soft delete operations - only handles privileged fields.
  Should only be called from authorized service modules.
  """
  def soft_delete_changeset(venue, attrs) do
    venue
    |> cast(attrs, [:deleted_at, :deleted_by, :merged_into_id])
    |> validate_required([:deleted_at, :deleted_by])
  end

  # Handle cleaning up image files when google_place_images is set to empty
  defp handle_google_place_images_change(changeset, venue) do
    case {get_change(changeset, :google_place_images), venue.google_place_images} do
      {[], images} when is_list(images) and length(images) > 0 ->
        # Only call delete if we're changing from non-empty to empty
        require Logger
        Logger.info("🗑️ Clearing Google Place images for venue: #{venue.name}")
        TriviaAdvisor.Services.GooglePlaceImageStore.delete_venue_images(venue)
        changeset
      _ ->
        changeset
    end
  end

  defp cleanup_url(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      "#" -> put_change(changeset, field, nil)
      url ->
        if String.match?(url, @url_regex) do
          changeset
        else
          put_change(changeset, field, nil)
        end
    end
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
    case Repo.get_by(__MODULE__, slug: slug, deleted_at: nil) do
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

  @doc """
  Callback that gets called before deleting a venue
  to clean up associated Google Place images
  """
  def before_delete(venue) do
    # Delete all associated Google Place images
    GooglePlaceImageStore.delete_venue_images(venue)
    venue
  end

  @doc """
  Callback to clean up images when the google_place_images field is updated to empty
  """
  def after_update(%{changes: %{google_place_images: []}} = changeset) do
    # If google_place_images was changed to an empty list, delete the images
    venue = changeset.data
    GooglePlaceImageStore.delete_venue_images(venue)
    changeset
  end
  def after_update(changeset), do: changeset
end

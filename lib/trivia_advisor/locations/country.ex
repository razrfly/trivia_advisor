defmodule TriviaAdvisor.Locations.Country do
  use Ecto.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Locations.City

  schema "countries" do
    field :name, :string
    field :code, :string
    field :slug, :string
    field :unsplash_gallery, :map

    has_many :cities, City

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(country, attrs) do
    country
    |> cast(attrs, [:code, :name, :unsplash_gallery])
    |> validate_required([:code, :name])
    |> generate_slug()
    |> unique_constraint(:code)
    |> unique_constraint(:slug)
  end

  defp generate_slug(%Ecto.Changeset{valid?: true, changes: %{name: name}} = changeset) do
    put_change(changeset, :slug, Slug.slugify(name))
  end

  defp generate_slug(changeset), do: changeset

  @doc """
  Fetches the currency code dynamically from the Countries library.
  """
  def currency_code(%__MODULE__{} = country), do: Countries.get(country.code).currency_code

  @doc """
  Fetches the continent dynamically.
  """
  def continent(%__MODULE__{} = country), do: Countries.get(country.code).continent

  @doc """
  Fetches the calling code dynamically.
  """
  def calling_code(%__MODULE__{} = country), do: Countries.get(country.code).country_code

  @doc """
  Fetches all country data dynamically.
  """
  def country_data(%__MODULE__{} = country), do: Countries.get(country.code)
end

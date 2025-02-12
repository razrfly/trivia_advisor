defmodule TriviaAdvisor.Locations.Country do
  use Ecto.Schema
  import Ecto.Changeset

  schema "countries" do
    field :code, :string
    field :name, :string

    has_many :cities, TriviaAdvisor.Locations.City

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(country, attrs) do
    country
    |> cast(attrs, [:code, :name])
    |> validate_required([:code, :name])
    |> unique_constraint(:code)
  end

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

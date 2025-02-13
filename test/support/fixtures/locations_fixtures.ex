defmodule TriviaAdvisor.LocationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TriviaAdvisor.Locations` context.
  """

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Country

  @doc """
  Generate a unique country code.
  """
  def unique_country_code, do: "some code#{System.unique_integer([:positive])}"

  @doc """
  Generate a country.
  """
  def country_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{
      code: "GB",  # Changed from US to GB to avoid conflicts
      name: "United Kingdom"
    })

    # Try to find existing country first
    case Repo.get_by(Country, code: attrs.code) do
      nil ->
        {:ok, country} =
          %Country{}
          |> Country.changeset(attrs)
          |> Repo.insert()
        country
      country ->
        country
    end
  end

  @doc """
  Generate a unique city slug.
  """
  def unique_city_slug, do: "some slug#{System.unique_integer([:positive])}"

  @doc """
  Generate a city.
  """
  def city_fixture(attrs \\ %{}) do
    country = country_fixture()
    unique_id = System.unique_integer([:positive])

    {:ok, city} =
      attrs
      |> Enum.into(%{
        name: "City #{unique_id}",  # Make name unique too
        slug: "city-#{unique_id}",  # Ensure unique slug
        country_id: country.id
      })
      |> TriviaAdvisor.Locations.create_city()

    city
  end

  @doc """
  Generate a unique venue place_id.
  """
  def unique_venue_place_id, do: "some place_id#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique venue slug.
  """
  def unique_venue_slug, do: "some slug#{System.unique_integer([:positive])}"

  @doc """
  Generate a venue.
  """
  def venue_fixture(attrs \\ %{}) do
    city = city_fixture()
    unique_id = System.unique_integer([:positive])

    attrs = Enum.into(attrs, %{
      name: "Venue #{unique_id}",  # Make name unique
      address: "some address",
      postcode: "some postcode",
      latitude: Decimal.new("51.5074"),
      longitude: Decimal.new("-0.1278"),
      place_id: "place_id_#{unique_id}",  # Make place_id unique
      phone: "some phone",
      website: "some website",
      city_id: city.id
    })

    {:ok, venue} =
      attrs
      |> TriviaAdvisor.Locations.create_venue()

    venue
  end
end

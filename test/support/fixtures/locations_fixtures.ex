defmodule TriviaAdvisor.LocationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TriviaAdvisor.Locations` context.
  """

  @doc """
  Generate a unique country code.
  """
  def unique_country_code, do: "some code#{System.unique_integer([:positive])}"

  @doc """
  Generate a country.
  """
  def country_fixture(attrs \\ %{}) do
    {:ok, country} =
      attrs
      |> Enum.into(%{
        title: "some title",
        name: "United States",
        code: "US",
        slug: "some-slug#{System.unique_integer()}"
      })
      |> TriviaAdvisor.Locations.create_country()

    country
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

    {:ok, city} =
      attrs
      |> Enum.into(%{
        name: "some name",
        slug: "some-slug#{System.unique_integer()}",
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

    {:ok, venue} =
      attrs
      |> Enum.into(%{
        address: "some address",
        name: "some name",
        slug: "some-slug#{System.unique_integer()}",
        postcode: "some postcode",
        latitude: "120.5",
        longitude: "120.5",
        place_id: "some place_id#{System.unique_integer()}",
        phone: "some phone",
        website: "some website",
        city_id: city.id
      })
      |> TriviaAdvisor.Locations.create_venue()

    venue
  end
end

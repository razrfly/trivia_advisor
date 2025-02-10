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
        code: unique_country_code(),
        name: "some name"
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
    {:ok, city} =
      attrs
      |> Enum.into(%{
        slug: unique_city_slug(),
        title: "some title"
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
    {:ok, venue} =
      attrs
      |> Enum.into(%{
        address: "some address",
        latitude: "120.5",
        longitude: "120.5",
        phone: "some phone",
        place_id: unique_venue_place_id(),
        postcode: "some postcode",
        slug: unique_venue_slug(),
        title: "some title",
        website: "some website"
      })
      |> TriviaAdvisor.Locations.create_venue()

    venue
  end
end

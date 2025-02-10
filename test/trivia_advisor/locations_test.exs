defmodule TriviaAdvisor.LocationsTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Locations

  describe "countries" do
    alias TriviaAdvisor.Locations.Country

    import TriviaAdvisor.LocationsFixtures

    @invalid_attrs %{code: nil, name: nil}

    test "list_countries/0 returns all countries" do
      country = country_fixture()
      assert Locations.list_countries() == [country]
    end

    test "get_country!/1 returns the country with given id" do
      country = country_fixture()
      assert Locations.get_country!(country.id) == country
    end

    test "create_country/1 with valid data creates a country" do
      valid_attrs = %{code: "some code", name: "some name"}

      assert {:ok, %Country{} = country} = Locations.create_country(valid_attrs)
      assert country.code == "some code"
      assert country.name == "some name"
    end

    test "create_country/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Locations.create_country(@invalid_attrs)
    end

    test "update_country/2 with valid data updates the country" do
      country = country_fixture()
      update_attrs = %{code: "some updated code", name: "some updated name"}

      assert {:ok, %Country{} = country} = Locations.update_country(country, update_attrs)
      assert country.code == "some updated code"
      assert country.name == "some updated name"
    end

    test "update_country/2 with invalid data returns error changeset" do
      country = country_fixture()
      assert {:error, %Ecto.Changeset{}} = Locations.update_country(country, @invalid_attrs)
      assert country == Locations.get_country!(country.id)
    end

    test "delete_country/1 deletes the country" do
      country = country_fixture()
      assert {:ok, %Country{}} = Locations.delete_country(country)
      assert_raise Ecto.NoResultsError, fn -> Locations.get_country!(country.id) end
    end

    test "change_country/1 returns a country changeset" do
      country = country_fixture()
      assert %Ecto.Changeset{} = Locations.change_country(country)
    end
  end

  describe "cities" do
    alias TriviaAdvisor.Locations.City

    import TriviaAdvisor.LocationsFixtures

    @invalid_attrs %{title: nil, slug: nil}

    test "list_cities/0 returns all cities" do
      city = city_fixture()
      assert Locations.list_cities() == [city]
    end

    test "get_city!/1 returns the city with given id" do
      city = city_fixture()
      assert Locations.get_city!(city.id) == city
    end

    test "create_city/1 with valid data creates a city" do
      valid_attrs = %{title: "some title", slug: "some slug"}

      assert {:ok, %City{} = city} = Locations.create_city(valid_attrs)
      assert city.title == "some title"
      assert city.slug == "some slug"
    end

    test "create_city/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Locations.create_city(@invalid_attrs)
    end

    test "update_city/2 with valid data updates the city" do
      city = city_fixture()
      update_attrs = %{title: "some updated title", slug: "some updated slug"}

      assert {:ok, %City{} = city} = Locations.update_city(city, update_attrs)
      assert city.title == "some updated title"
      assert city.slug == "some updated slug"
    end

    test "update_city/2 with invalid data returns error changeset" do
      city = city_fixture()
      assert {:error, %Ecto.Changeset{}} = Locations.update_city(city, @invalid_attrs)
      assert city == Locations.get_city!(city.id)
    end

    test "delete_city/1 deletes the city" do
      city = city_fixture()
      assert {:ok, %City{}} = Locations.delete_city(city)
      assert_raise Ecto.NoResultsError, fn -> Locations.get_city!(city.id) end
    end

    test "change_city/1 returns a city changeset" do
      city = city_fixture()
      assert %Ecto.Changeset{} = Locations.change_city(city)
    end
  end

  describe "venues" do
    alias TriviaAdvisor.Locations.Venue

    import TriviaAdvisor.LocationsFixtures

    @invalid_attrs %{address: nil, title: nil, postcode: nil, latitude: nil, longitude: nil, place_id: nil, phone: nil, website: nil, slug: nil}

    test "list_venues/0 returns all venues" do
      venue = venue_fixture()
      assert Locations.list_venues() == [venue]
    end

    test "get_venue!/1 returns the venue with given id" do
      venue = venue_fixture()
      assert Locations.get_venue!(venue.id) == venue
    end

    test "create_venue/1 with valid data creates a venue" do
      valid_attrs = %{address: "some address", title: "some title", postcode: "some postcode", latitude: "120.5", longitude: "120.5", place_id: "some place_id", phone: "some phone", website: "some website", slug: "some slug"}

      assert {:ok, %Venue{} = venue} = Locations.create_venue(valid_attrs)
      assert venue.address == "some address"
      assert venue.title == "some title"
      assert venue.postcode == "some postcode"
      assert venue.latitude == Decimal.new("120.5")
      assert venue.longitude == Decimal.new("120.5")
      assert venue.place_id == "some place_id"
      assert venue.phone == "some phone"
      assert venue.website == "some website"
      assert venue.slug == "some slug"
    end

    test "create_venue/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Locations.create_venue(@invalid_attrs)
    end

    test "update_venue/2 with valid data updates the venue" do
      venue = venue_fixture()
      update_attrs = %{address: "some updated address", title: "some updated title", postcode: "some updated postcode", latitude: "456.7", longitude: "456.7", place_id: "some updated place_id", phone: "some updated phone", website: "some updated website", slug: "some updated slug"}

      assert {:ok, %Venue{} = venue} = Locations.update_venue(venue, update_attrs)
      assert venue.address == "some updated address"
      assert venue.title == "some updated title"
      assert venue.postcode == "some updated postcode"
      assert venue.latitude == Decimal.new("456.7")
      assert venue.longitude == Decimal.new("456.7")
      assert venue.place_id == "some updated place_id"
      assert venue.phone == "some updated phone"
      assert venue.website == "some updated website"
      assert venue.slug == "some updated slug"
    end

    test "update_venue/2 with invalid data returns error changeset" do
      venue = venue_fixture()
      assert {:error, %Ecto.Changeset{}} = Locations.update_venue(venue, @invalid_attrs)
      assert venue == Locations.get_venue!(venue.id)
    end

    test "delete_venue/1 deletes the venue" do
      venue = venue_fixture()
      assert {:ok, %Venue{}} = Locations.delete_venue(venue)
      assert_raise Ecto.NoResultsError, fn -> Locations.get_venue!(venue.id) end
    end

    test "change_venue/1 returns a venue changeset" do
      venue = venue_fixture()
      assert %Ecto.Changeset{} = Locations.change_venue(venue)
    end
  end
end

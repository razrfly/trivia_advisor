defmodule TriviaAdvisor.LocationsTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Locations.Country
  alias TriviaAdvisor.Locations.City

  describe "find_or_create_country/1" do
    test "returns existing country if found" do
      country_data = Countries.get("GB")
      {:ok, country} = Repo.insert(%Country{
        code: country_data.alpha2,
        name: country_data.name
      })

      assert {:ok, found_country} = Locations.find_or_create_country("GB")
      assert found_country.id == country.id
      assert found_country.code == country_data.alpha2
      assert found_country.name == country_data.name

      # Test dynamic data retrieval
      assert Country.currency_code(found_country) == country_data.currency_code
      assert Country.continent(found_country) == country_data.continent
      assert Country.calling_code(found_country) == country_data.country_code
    end

    test "creates new country if not found" do
      assert {:ok, country} = Locations.find_or_create_country("AU")
      country_data = Countries.get("AU")

      # Test stored fields
      assert country.code == country_data.alpha2
      assert country.name == country_data.name

      # Test dynamic data retrieval
      assert Country.currency_code(country) == country_data.currency_code
      assert Country.continent(country) == country_data.continent
      assert Country.calling_code(country) == country_data.country_code

      # Verify DB storage
      db_country = Repo.get_by(Country, code: "AU")
      assert db_country.code == country_data.alpha2
    end

    test "returns error for invalid country code" do
      assert {:error, "Invalid country code"} = Locations.find_or_create_country("XX")
    end

    test "maintains unique constraint on country code" do
      {:ok, _} = Locations.find_or_create_country("GB")
      {:ok, country2} = Locations.find_or_create_country("GB")
      country_data = Countries.get("GB")

      assert Repo.aggregate(Country, :count) == 1
      assert country2.code == country_data.alpha2
      assert country2.name == country_data.name
    end
  end

  describe "find_or_create_city/2" do
    test "returns existing city if found" do
      {:ok, country} = Locations.find_or_create_country("GB")
      {:ok, city} = Repo.insert(%City{
        name: "London",
        country_id: country.id,
        slug: "london"
      })

      assert {:ok, found_city} = Locations.find_or_create_city("London", "GB")
      assert found_city.id == city.id
      assert found_city.name == "London"
      assert found_city.country_id == country.id
    end

    test "creates new city if not found" do
      assert {:ok, city} = Locations.find_or_create_city("Manchester", "GB")
      assert city.name == "Manchester"
      assert city.slug == "manchester"

      country = Repo.get!(Country, city.country_id)
      assert country.code == "GB"

      db_city = Repo.get_by(City, name: "Manchester")
      assert db_city.name == "Manchester"
    end

    test "ensures city belongs to correct country" do
      assert {:ok, london_uk} = Locations.find_or_create_city("London", "GB")
      assert {:ok, london_ca} = Locations.find_or_create_city("London, Ontario", "CA")

      uk_country = Repo.get!(Country, london_uk.country_id)
      ca_country = Repo.get!(Country, london_ca.country_id)

      assert uk_country.code == "GB"
      assert ca_country.code == "CA"
      assert london_uk.country_id != london_ca.country_id
      assert london_uk.slug == "london"
      assert london_ca.slug == "london-ontario"
    end

    test "handles invalid country code" do
      assert {:error, "Invalid country code"} = Locations.find_or_create_city("Invalid City", "XX")
    end
  end
end

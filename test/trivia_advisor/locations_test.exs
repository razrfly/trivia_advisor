defmodule TriviaAdvisor.LocationsTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Locations.Country

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
end

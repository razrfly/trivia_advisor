defmodule TriviaAdvisor.LocationsTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Locations.Country

  describe "find_or_create_country/1" do
    test "returns existing country if found" do
      # Setup
      {:ok, country} = Repo.insert(%Country{code: "GB", name: "United Kingdom of Great Britain and Northern Ireland"})

      # Test
      assert {:ok, found_country} = Locations.find_or_create_country("GB")
      assert found_country.id == country.id
      assert found_country.code == "GB"
      assert found_country.name == "United Kingdom of Great Britain and Northern Ireland"
    end

    test "creates new country if not found" do
      assert {:ok, country} = Locations.find_or_create_country("AU")
      assert country.code == "AU"
      assert country.name == "Australia"

      # Verify it was saved to DB
      assert Repo.get_by(Country, code: "AU")
    end

    test "returns error for invalid country code" do
      assert {:error, "Invalid country code"} = Locations.find_or_create_country("XX")
    end

    test "can fetch additional country data from Countries library" do
      {:ok, country} = Locations.find_or_create_country("GB")
      country_data = Countries.get(country.code)

      assert country_data.alpha2 == "GB"
      assert country_data.name == "United Kingdom of Great Britain and Northern Ireland"
      assert country_data.currency_code == "GBP"
      assert country_data.continent == "Europe"
      assert country_data.country_code == "44"
    end

    test "maintains unique constraint on country code" do
      {:ok, _} = Locations.find_or_create_country("GB")
      {:ok, country2} = Locations.find_or_create_country("GB")

      assert Repo.aggregate(Country, :count) == 1
      assert country2.code == "GB"
      assert country2.name == "United Kingdom of Great Britain and Northern Ireland"
    end
  end
end

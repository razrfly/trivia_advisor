defmodule TriviaAdvisor.LocationsTest do
  use TriviaAdvisor.DataCase
  import Mox

  # Ensure mocks are verified when the test exits
  setup :verify_on_exit!

  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Locations.Country
  alias TriviaAdvisor.Locations.City
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Scraping.MockGoogleLookup
  alias TriviaAdvisor.Utils.Slug
  alias TriviaAdvisor.Repo

  # Define a helper function to set up expectations
  defp mock_lookup_address(fun) do
    MockGoogleLookup
    |> expect(:lookup_address, fun)
  end

  describe "find_or_create_country/1" do
    test "returns existing country if found" do
      country_data = Countries.get("GB")
      {:ok, country} = Repo.insert(%Country{
        code: country_data.alpha2,
        name: country_data.name,
        slug: Slug.slugify(country_data.name)
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
      assert {:ok, london_us} = Locations.find_or_create_city("London", "US")

      assert london_uk.name == "London"
      assert london_us.name == "London"
      assert london_uk.slug == "london"
      assert london_us.slug == "london-us"

      refute london_uk.id == london_us.id
      refute london_uk.country_id == london_us.country_id
    end

    test "handles invalid country code" do
      assert {:error, "Invalid country code"} = Locations.find_or_create_city("Invalid City", "XX")
    end
  end

  describe "find_or_create_venue/1" do
    test "returns existing venue if place_id matches" do
      {:ok, city} = Locations.find_or_create_city("London", "GB")
      {:ok, venue} = Repo.insert(%Venue{
        city_id: city.id,
        name: "The Crown Tavern",
        address: "43 Clerkenwell Green",
        latitude: Decimal.new("51.5225"),
        longitude: Decimal.new("-0.1057"),
        place_id: "ChIJN1t_tDeuEmsRUsoyG83frY4",
        slug: "the-crown-tavern"
      })

      # Mock the Google API response
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5225,
          lng: -0.1057,
          place_id: "ChIJN1t_tDeuEmsRUsoyG83frY4",
          city: "London",
          country_code: "GB",
          postcode: "EC1R 0EG"
        }}
      end)

      assert {:ok, found_venue} = Locations.find_or_create_venue(%{
        "title" => "The Crown Tavern",
        "address" => "43 Clerkenwell Green"
      })

      assert found_venue.id == venue.id
    end

    test "creates new venue when none exists" do
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5074,
          lng: -0.1278,
          place_id: "abc123",
          formatted_address: "123 London Road, London, UK",
          city: "London",
          country_code: "GB"
        }}
      end)

      assert {:ok, venue} =
              Locations.find_or_create_venue(%{
                "name" => "New Pub",
                "address" => "123 London Road",
                "phone" => "123456",
                "website" => "http://example.com"
              })

      assert venue.phone == "123456"
      assert venue.website == "http://example.com"
      assert venue.city.name == "London"
      assert venue.city.country.code == "GB"
    end

    test "returns error if address is missing" do
      assert {:error, "Address is required"} = Locations.find_or_create_venue(%{})
    end

    test "returns error when Google API fails" do
      mock_lookup_address(fn _address -> {:error, "Google API error"} end)

      assert {:error, "Google API error"} = Locations.find_or_create_venue(%{
        "title" => "Some Pub",
        "address" => "Unknown Address"
      })
    end

    test "handles incomplete Google API response" do
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5074,
          lng: -0.1278,
          # Missing city and country_code
          place_id: "incomplete_data"
        }}
      end)

      assert {:error, "City name missing"} = Locations.find_or_create_venue(%{
        "title" => "Incomplete Pub",
        "address" => "123 Unknown Road"
      })
    end

    test "finds venue by coordinates even with different address format" do
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5074,
          lng: -0.1278,
          place_id: "abc124",
          formatted_address: "10 Downing St, London, UK",
          city: "London",
          country_code: "GB"
        }}
      end)

      {:ok, venue1} = Locations.find_or_create_venue(%{
        "name" => "Downing Street Pub",
        "address" => "10 Downing St, London"
      })

      assert venue1.city.name == "London"

      # Reset the mock and use a different address but same coordinates
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5074,
          lng: -0.1278,
          place_id: "different123",
          formatted_address: "10 Downing Street, Westminster, London, UK",
          city: "London",
          country_code: "GB"
        }}
      end)

      # Should find the same venue by proximity
      {:ok, venue2} = Locations.find_or_create_venue(%{
        "name" => "Downing Street Pub",
        "address" => "10 Downing Street, Westminster, London"
      })

      assert venue1.id == venue2.id
    end

    test "handles city name variations" do
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5074,
          lng: -0.1278,
          place_id: "abc125",
          formatted_address: "London Address",
          city: "London (Greater London)",
          country_code: "GB"
        }}
      end)

      {:ok, venue1} = Locations.find_or_create_venue(%{
        "name" => "London Venue",
        "address" => "London Address"
      })

      assert venue1.city.name == "London"

      # Reset the mock with a different variation of London
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5074,
          lng: -0.1278,
          place_id: "abc126",
          formatted_address: "Different London Address",
          city: "London, Greater London",
          country_code: "GB"
        }}
      end)

      {:ok, venue2} = Locations.find_or_create_venue(%{
        "name" => "Another London Venue",
        "address" => "Another London Address"
      })

      # Should be same city
      assert venue1.city.id == venue2.city.id
      assert venue2.city.name == "London"
    end

    test "finds venue by proximity even with different place_id" do
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5225,
          lng: -0.1057,
          place_id: "place1",
          formatted_address: "43 Clerkenwell Green, London EC1R 0DU, UK",
          city: "London",
          country_code: "GB"
        }}
      end)

      {:ok, venue1} = Locations.find_or_create_venue(%{
        "name" => "Clerkenwell Pub",
        "address" => "43 Clerkenwell Green"
      })

      # Same location, different place_id
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5225,
          lng: -0.1057,
          place_id: "place2",
          formatted_address: "43 Clerkenwell Green, London EC1R 0DU, UK",
          city: "London",
          country_code: "GB"
        }}
      end)

      {:ok, venue2} = Locations.find_or_create_venue(%{
        "name" => "Clerkenwell Pub",
        "address" => "43 Clerkenwell Green, London"
      })

      # Should find the same venue by proximity
      assert venue1.id == venue2.id
    end

    test "handles missing city in Google API response" do
      mock_lookup_address(fn _address ->
        {:ok, %{
          lat: 51.5074,
          lng: -0.1278,
          place_id: "no_city",
          country_code: "GB"
          # city is missing
        }}
      end)

      assert {:error, "City name missing"} = Locations.find_or_create_venue(%{
        "title" => "No City Pub",
        "address" => "Unknown Location"
      })
    end
  end
end

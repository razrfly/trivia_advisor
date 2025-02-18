defmodule TriviaAdvisor.Events.EventTest do
  use TriviaAdvisor.DataCase
  use ExUnit.Case

  alias TriviaAdvisor.Events.Event
  alias TriviaAdvisor.Locations.{Country, City, Venue}

  # ✅ Keep all currency parsing tests
  describe "currency parsing" do
    setup do
      # Set up test data
      {:ok, country} = Repo.insert(%Country{
        code: "GB",
        name: "United Kingdom",
        slug: TriviaAdvisor.Utils.Slug.slugify("United Kingdom")
      })
      {:ok, city} = Repo.insert(%City{
        name: "London",
        country_id: country.id,
        slug: "london"
      })
      {:ok, venue} = Repo.insert(%Venue{
        name: "Test Pub",
        city_id: city.id,
        slug: "test-pub",
        address: "123 Test St",
        latitude: Decimal.new("51.5074"),
        longitude: Decimal.new("-0.1278")
      })

      {:ok, country_de} = Repo.insert(%Country{
        code: "DE",
        name: "Germany",
        slug: TriviaAdvisor.Utils.Slug.slugify("Germany")
      })
      {:ok, city_de} = Repo.insert(%City{
        name: "Berlin",
        country_id: country_de.id,
        slug: "berlin"
      })
      {:ok, venue_de} = Repo.insert(%Venue{
        name: "Test Bar DE",
        city_id: city_de.id,
        address: "456 Test St",
        latitude: Decimal.new("52.5200"),
        longitude: Decimal.new("13.4050"),
        slug: "test-bar-de"
      })

      %{venue: venue, city: city, country: country, venue_de: venue_de}
    end

    test "converts GB amounts correctly", %{venue: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("£3.50", venue) == 350
      assert Event.parse_currency("3.50", venue) == 350
      assert Event.parse_currency("£10", venue) == 1000
    end

    test "converts DE amounts correctly", %{venue_de: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("€4.50", venue) == 450
      assert Event.parse_currency("4.50", venue) == 450
      assert Event.parse_currency("€10", venue) == 1000
    end

    test "handles free events", %{venue: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("Free", venue) == nil
    end

    test "handles invalid inputs", %{venue: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("abc", venue) == nil
      assert Event.parse_currency(nil, venue) == nil
    end

    test "raises error when venue has no city", %{venue: _venue} do
      city = %City{name: "No Country City", slug: "no-country-city", country: nil, __meta__: %Ecto.Schema.Metadata{state: :loaded}}
      venue = %Venue{name: "No Country Venue", city: city, address: "012 Test St", latitude: 0.0, longitude: 0.0, slug: "no-country-venue", __meta__: %Ecto.Schema.Metadata{state: :loaded}}

      assert_raise RuntimeError, "Venue's city must have an associated country", fn ->
        Event.parse_currency("£3.50", venue)
      end
    end
  end

  # ✅ Keep all frequency parsing tests
  describe "parse_frequency/1" do
    test "handles weekly variations" do
      assert Event.parse_frequency("every week") == :weekly
      assert Event.parse_frequency("WEEKLY") == :weekly
      assert Event.parse_frequency("each week") == :weekly
    end

    test "handles biweekly variations" do
      assert Event.parse_frequency("every 2 weeks") == :biweekly
      assert Event.parse_frequency("bi-weekly") == :biweekly
      assert Event.parse_frequency("fortnightly") == :biweekly
    end

    test "handles monthly variations" do
      assert Event.parse_frequency("every month") == :monthly
      assert Event.parse_frequency("Monthly") == :monthly
    end

    test "handles irregular cases" do
      assert Event.parse_frequency("") == :irregular
      assert Event.parse_frequency(nil) == :irregular
      assert Event.parse_frequency("random text") == :irregular
    end
  end
end

defmodule TriviaAdvisor.Events.EventTest do
  use TriviaAdvisor.DataCase
  alias TriviaAdvisor.Events.Event
  alias TriviaAdvisor.Locations.{Country, City, Venue}

  describe "currency parsing" do
    setup do
      # Set up test data
      {:ok, country_gb} = Repo.insert(%Country{code: "GB", name: "United Kingdom"})
      {:ok, city} = Repo.insert(%City{
        name: "London",
        country_id: country_gb.id,
        slug: "london"
      })
      {:ok, venue_gb} = Repo.insert(%Venue{
        name: "Test Pub GB",
        city_id: city.id,
        address: "123 Test St",
        latitude: 51.5074,
        longitude: -0.1278,
        slug: "test-pub-gb"
      })

      {:ok, country_de} = Repo.insert(%Country{code: "DE", name: "Germany"})
      {:ok, city_de} = Repo.insert(%City{
        name: "Berlin",
        country_id: country_de.id,
        slug: "berlin"
      })
      {:ok, venue_de} = Repo.insert(%Venue{
        name: "Test Bar DE",
        city_id: city_de.id,
        address: "456 Test St",
        latitude: 52.5200,
        longitude: 13.4050,
        slug: "test-bar-de"
      })

      %{
        venue_gb: venue_gb,
        venue_de: venue_de,
        venue_no_city: build_venue_without_city(),
        venue_no_country: build_venue_without_country()
      }
    end

    defp build_venue_without_city do
      %Venue{
        name: "No City Venue",
        address: "789 Test St",
        latitude: 0.0,
        longitude: 0.0,
        slug: "no-city-venue"
      }
    end

    defp build_venue_without_country do
      city = %City{
        name: "No Country City",
        slug: "no-country-city",
        country: nil,
        __meta__: %Ecto.Schema.Metadata{state: :loaded}
      }

      %Venue{
        name: "No Country Venue",
        city: city,
        address: "012 Test St",
        latitude: 0.0,
        longitude: 0.0,
        slug: "no-country-venue",
        __meta__: %Ecto.Schema.Metadata{state: :loaded}
      }
    end

    test "converts GB amounts correctly", %{venue_gb: venue} do
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

    test "handles free events", %{venue_gb: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("Free", venue) == nil
      assert Event.parse_currency("No charge", venue) == nil
    end

    test "handles invalid inputs", %{venue_gb: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("abc", venue) == nil
      assert Event.parse_currency(nil, venue) == nil
    end

    test "fails when country is missing", %{venue_gb: _venue} do
      # Create a venue with a city that has no country
      city = %City{
        name: "No Country City",
        slug: "no-country-city",
        country: nil,  # Explicitly set country to nil
        __meta__: %Ecto.Schema.Metadata{state: :loaded}
      }
      venue = %Venue{
        name: "No Country Venue",
        city: city,  # Don't use force: true, just set the struct directly
        address: "012 Test St",
        latitude: 0.0,
        longitude: 0.0,
        slug: "no-country-venue",
        __meta__: %Ecto.Schema.Metadata{state: :loaded},
        city_id: nil
      }

      # No need to preload since we've built the struct with associations
      assert_raise RuntimeError, "Venue's city must have an associated country", fn ->
        Event.parse_currency("£3.50", venue)
      end
    end

    test "handles integer inputs", %{venue_gb: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency(350, venue) == 350
    end

    test "handles invalid price format gracefully", %{venue_gb: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("invalid", venue) == nil
      assert Event.parse_currency("abc123", venue) == nil
      assert Event.parse_currency("£abc", venue) == nil
    end

    test "raises error when venue has no city", %{venue_no_city: venue} do
      venue = Repo.preload(venue, city: :country)
      assert_raise RuntimeError, "Venue must have an associated city", fn ->
        Event.parse_currency("£3.50", venue)
      end
    end

    test "raises error when city has no country", %{venue_no_country: _venue} do
      # Create a venue with a city that has no country
      city = %City{
        name: "No Country City",
        slug: "no-country-city",
        country: nil,  # Explicitly set country to nil
        __meta__: %Ecto.Schema.Metadata{state: :loaded}
      }
      venue = %Venue{
        name: "No Country Venue",
        city: city,  # Set city directly
        address: "012 Test St",
        latitude: 0.0,
        longitude: 0.0,
        slug: "no-country-venue",
        __meta__: %Ecto.Schema.Metadata{state: :loaded}
      }

      assert_raise RuntimeError, "Venue's city must have an associated country", fn ->
        Event.parse_currency("£3.50", venue)
      end
    end

    test "validates entry fee in changeset", %{venue_gb: venue} do
      # Test valid fee
      changeset = Event.changeset(%Event{}, %{
        day_of_week: 1,
        start_time: ~T[14:00:00],
        frequency: :weekly,
        entry_fee_cents: 350,
        venue_id: venue.id
      })
      assert changeset.valid?

      # Test negative fee
      changeset = Event.changeset(%Event{}, %{
        day_of_week: 1,
        start_time: ~T[14:00:00],
        frequency: :weekly,
        entry_fee_cents: -100,
        venue_id: venue.id
      })
      refute changeset.valid?
      assert {"must be a non-negative integer or nil", _} =
        changeset.errors[:entry_fee_cents]
    end

    test "handles amounts without currency symbols", %{venue_gb: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("3.50", venue) == 350
      assert Event.parse_currency("10.00", venue) == 1000
      assert Event.parse_currency("42", venue) == 4200
    end

    test "rejects invalid numeric formats", %{venue_gb: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("3.5.0", venue) == nil
      assert Event.parse_currency("-3.50", venue) == nil
      assert Event.parse_currency("3.50.00", venue) == nil
      assert Event.parse_currency("3.5O", venue) == nil  # O instead of 0
    end

    test "handles whitespace in amounts", %{venue_gb: venue} do
      venue = Repo.preload(venue, city: :country)
      assert Event.parse_currency("  3.50  ", venue) == 350
      assert Event.parse_currency("£  3.50", venue) == 350
      assert Event.parse_currency("3.50  £", venue) == nil  # Symbol must be prefix
    end
  end
end

defmodule TriviaAdvisorWeb.HomeLive.IndexTest do
  use TriviaAdvisorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TriviaAdvisor.LocationsFixtures
  import TriviaAdvisor.EventsFixtures

  setup do
    # Create a test country, city, and venue
    country = country_fixture(%{code: "GB", name: "United Kingdom"})
    city = city_fixture(%{country_id: country.id, name: "London"})

    # Create a few test venues
    venue1 = venue_fixture(%{
      name: "Test Venue 1",
      city_id: city.id,
      rating: 4.5
    })

    venue2 = venue_fixture(%{
      name: "Test Venue 2",
      city_id: city.id,
      rating: 3.8
    })

    # Create events with entry fees for the venues
    event1 = event_fixture(%{
      name: "Test Event 1",
      venue_id: venue1.id,
      day_of_week: 4,
      start_time: ~T[19:30:00],
      entry_fee_cents: 500  # £5.00
    })

    event2 = event_fixture(%{
      name: "Test Event 2",
      venue_id: venue2.id,
      day_of_week: 2,
      start_time: ~T[20:00:00],
      entry_fee_cents: 300  # £3.00
    })

    # Get venues with preloaded events
    venues = [
      %{venue1 | events: [event1]},
      %{venue2 | events: [event2]}
    ]

    %{venues: venues, city: city, country: country, events: [event1, event2]}
  end

  describe "Home page" do
    test "renders featured venues, popular cities, and upcoming events", %{conn: conn, venues: _venues} do
      {:ok, view, html} = live(conn, ~p"/")

      # Test that the page loads with the right title
      assert html =~ "TriviaAdvisor - Find the Best Pub Quizzes Near You"
      assert html =~ "Find the Best Pub Quizzes Near You"

      # Test that the page has the main sections
      assert has_element?(view, "[data-testid='featured-venues']")
      assert has_element?(view, "[data-testid='popular-cities']")
      assert has_element?(view, "[data-testid='upcoming-events']")

      # Test that venue cards are rendered properly
      assert has_element?(view, ".venue-card")

      # Test that at least one of the test venues appears on the page
      assert html =~ "Test Venue 1" || html =~ "Test Venue 2"

      # Test that venue slugs are generated
      assert html =~ "test-venue-1" || html =~ "test-venue-2"

      # Test that star ratings are displayed
      assert html =~ "★" # Check for star symbol in rating

      # Test that entry fees are correctly displayed with currency
      assert html =~ "Entry: £" # Check for GBP currency in entry fee
    end
  end
end

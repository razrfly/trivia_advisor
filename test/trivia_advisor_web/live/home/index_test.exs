defmodule TriviaAdvisorWeb.HomeLive.IndexTest do
  use TriviaAdvisorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TriviaAdvisor.LocationsFixtures

  setup do
    # Create a test country, city, and venue
    country = country_fixture(%{code: "GB", name: "United Kingdom"})
    city = city_fixture(%{country_id: country.id, name: "London"})

    # Create a few test venues
    venue1 = venue_fixture(%{
      name: "Test Venue 1",
      day_of_week: 4,
      start_time: "7:30 PM",
      entry_fee_cents: 500,
      description: "Test venue description",
      city_id: city.id,
      rating: 4.5
    })

    venue2 = venue_fixture(%{
      name: "Test Venue 2",
      day_of_week: 2,
      start_time: "8:00 PM",
      entry_fee_cents: 300,
      description: "Another test venue",
      city_id: city.id,
      rating: 3.8
    })

    %{venues: [venue1, venue2], city: city, country: country}
  end

  describe "Home page" do
    test "renders featured venues, popular cities, and upcoming events", %{conn: conn, venues: [venue1, venue2]} do
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
      assert html =~ venue1.name || html =~ venue2.name

      # Test that venue slugs are generated
      venue1_slug = String.downcase(venue1.name) |> String.replace(~r/[^a-z0-9]+/, "-")
      venue2_slug = String.downcase(venue2.name) |> String.replace(~r/[^a-z0-9]+/, "-")

      assert html =~ venue1_slug || html =~ venue2_slug

      # Test that ratings are displayed
      assert html =~ "★" # Check for star symbol in rating
    end
  end
end

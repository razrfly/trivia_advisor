defmodule TriviaAdvisor.TestFixtures do
  @moduledoc """
  Contains mock data fixtures for testing and development.
  These fixtures should only be used in test environment or during development.
  """

  @doc """
  Returns mock featured venues for testing.
  """
  def mock_featured_venues do
    [
      %{
        id: "1",
        name: "Test Venue 1",
        address: "123 Main Street",
        city: %{name: "London", country: %{name: "United Kingdom", code: "GB"}},
        rating: 4.5,
        description: "Popular pub with weekly trivia nights and great atmosphere",
        entry_fee_cents: 500,
        day_of_week: 4,
        start_time: ~T[19:30:00],
        hero_image_url: "https://images.unsplash.com/photo-1560840881-4bbcd415a9ab?q=80&w=2000",
        slug: "test-venue-1"
      },
      %{
        id: "2",
        name: "Test Venue 2",
        address: "456 High Street",
        city: %{name: "Manchester", country: %{name: "United Kingdom", code: "GB"}},
        rating: 3.8,
        description: "Specialized trivia venue with themed quiz nights",
        entry_fee_cents: 300,
        day_of_week: 2,
        start_time: ~T[20:00:00],
        hero_image_url: "https://images.unsplash.com/photo-1572116469696-31de0f17cc34?q=80&w=2000",
        slug: "test-venue-2"
      },
      %{
        id: "3",
        name: "Brainy Bar",
        address: "789 Park Avenue",
        city: %{name: "Edinburgh", country: %{name: "United Kingdom", code: "GB"}},
        rating: 4.2,
        description: "Fun pub with challenging quiz questions and great prizes",
        entry_fee_cents: 0,
        day_of_week: 3,
        start_time: ~T[19:00:00],
        hero_image_url: "https://images.unsplash.com/photo-1583227122027-d2d360c66d3c?q=80&w=2000"
      },
      %{
        id: "4",
        name: "Trivia Tavern",
        address: "101 River Road",
        city: %{name: "Bristol", country: %{name: "United Kingdom", code: "GB"}},
        rating: 4.0,
        description: "Traditional pub with weekly general knowledge quizzes",
        entry_fee_cents: 200,
        day_of_week: 1,
        start_time: ~T[20:30:00],
        hero_image_url: "https://images.unsplash.com/photo-1546726747-421c6d69c929?q=80&w=2000"
      }
    ]
  end

  @doc """
  Returns mock popular cities for testing.
  """
  def mock_popular_cities do
    [
      %{id: "1", name: "London", country_name: "United Kingdom", venue_count: 120, image_url: "https://test.com/london.jpg", slug: "london"},
      %{id: "2", name: "New York", country_name: "United States", venue_count: 87, image_url: "https://test.com/ny.jpg", slug: "new-york"},
      %{id: "3", name: "Sydney", country_name: "Australia", venue_count: 45, image_url: "https://test.com/sydney.jpg", slug: "sydney"},
      %{id: "4", name: "Berlin", country_name: "Germany", venue_count: 35, image_url: "https://test.com/berlin.jpg", slug: "berlin"},
      %{id: "5", name: "Dublin", country_name: "Ireland", venue_count: 30, image_url: "https://test.com/dublin.jpg", slug: "dublin"},
      %{id: "6", name: "Toronto", country_name: "Canada", venue_count: 28, image_url: "https://test.com/toronto.jpg", slug: "toronto"}
    ]
  end

  @doc """
  Returns mock upcoming events for testing.
  """
  def mock_upcoming_events do
    [
      %{
        name: "The Ultimate Pub Quiz",
        venue_id: "1",
        day: "Thursday",
        date: "23",
        time: "7:30 PM",
        price: "$5",
        free?: false
      },
      %{
        name: "Geek Trivia Night",
        venue_id: "2",
        day: "Tuesday",
        date: "28",
        time: "8:00 PM",
        price: "$3",
        free?: false
      },
      %{
        name: "Music & Movies Quiz",
        venue_id: "3",
        day: "Wednesday",
        date: "29",
        time: "7:00 PM",
        price: "Free",
        free?: true
      },
      %{
        name: "General Knowledge Challenge",
        venue_id: "4",
        day: "Monday",
        date: "27",
        time: "8:30 PM",
        price: "$2",
        free?: false
      }
    ]
  end
end

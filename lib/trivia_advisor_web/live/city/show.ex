defmodule TriviaAdvisorWeb.CityLive.Show do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Services.UnsplashService
  require Logger

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Fetch the city by slug
    case get_city_data(slug) do
      {:ok, city_data} ->
        {:ok,
         socket
         |> assign(:page_title, "#{city_data.name} - Trivia Venues")
         |> assign(:city, city_data)
         |> assign(:venues, get_venues_for_city(city_data.id))}

      {:error, _} ->
        {:ok,
         socket
         |> assign(:page_title, "City Not Found")
         |> assign(:city, %{
           id: nil,
           name: "Unknown City",
           country_name: "Unknown Country",
           venue_count: 0,
           image_url: nil
         })
         |> assign(:venues, [])}
    end
  end

  @impl true
  def handle_params(%{"slug" => slug}, _, socket) do
    {:noreply,
     socket
     |> assign(:slug, slug)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- City Hero Section -->
      <div class="relative">
        <div class="h-64 overflow-hidden sm:h-80 lg:h-96">
          <img
            src={@city.image_url || "https://placehold.co/1200x400?text=#{@city.name}"}
            alt={@city.name}
            class="h-full w-full object-cover"
          />
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent"></div>
        <div class="absolute bottom-0 w-full p-4 text-white sm:p-6">
          <div class="mx-auto max-w-7xl">
            <h1 class="text-3xl font-bold sm:text-4xl md:text-5xl"><%= @city.name %></h1>
            <p class="text-xl text-white/80"><%= @city.venue_count %> Venues • <%= @city.country_name %></p>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <!-- Venues Section -->
        <div>
          <h2 class="mb-6 text-2xl font-bold text-gray-900">Trivia Venues in <%= @city.name %></h2>
          <p class="mb-8 text-lg text-gray-600">Discover the best pub quizzes and trivia nights in <%= @city.name %>.</p>

          <%= if length(@venues) > 0 do %>
            <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              <%= for venue <- @venues do %>
                <div class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm transition hover:shadow">
                  <div class="relative h-48">
                    <img
                      src={venue.hero_image_url || "https://placehold.co/600x400?text=#{venue.name}"}
                      alt={venue.name}
                      class="h-full w-full object-cover"
                    />
                    <div class="absolute right-2 top-2 rounded bg-white p-1 text-yellow-400">
                      <%= if venue.rating do %>
                        <div class="flex items-center">
                          <span class="mr-1 text-sm font-bold"><%= venue.rating %></span>
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                            <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118l-2.8-2.034c-.783-.57-.38-1.81.588-1.81h3.462a1 1 0 00.95-.69l1.07-3.292z" />
                          </svg>
                        </div>
                      <% else %>
                        <div class="flex items-center">
                          <span class="mr-1 text-sm font-medium text-gray-600">New</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                  <div class="p-4">
                    <h3 class="mb-1 text-lg font-bold text-gray-900"><%= venue.name %></h3>
                    <p class="mb-2 text-sm text-gray-600"><%= venue.address %></p>
                    <div class="mb-3 flex items-center text-sm text-gray-600">
                      <span class="font-medium text-indigo-600"><%= format_day(venue.day_of_week) %>s</span>
                      <span class="mx-2">•</span>
                      <span><%= venue.start_time %></span>
                      <span class="mx-2">•</span>
                      <span><%= venue.entry_fee %></span>
                    </div>
                    <p class="mb-4 text-sm text-gray-600 line-clamp-3"><%= venue.description %></p>
                    <a
                      href={~p"/venues/#{venue.id}"}
                      class="mt-2 inline-flex items-center text-sm font-medium text-indigo-600 hover:text-indigo-800"
                    >
                      View details
                      <svg class="ml-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M3 10a.75.75 0 01.75-.75h10.638L10.23 5.29a.75.75 0 111.04-1.08l5.5 5.25a.75.75 0 010 1.08l-5.5 5.25a.75.75 0 11-1.04-1.08l4.158-3.96H3.75A.75.75 0 013 10z" clip-rule="evenodd" />
                      </svg>
                    </a>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="rounded-lg border border-gray-200 bg-white p-8 text-center">
              <h3 class="mb-2 text-lg font-semibold text-gray-900">No venues found</h3>
              <p class="text-gray-600">We couldn't find any trivia venues in <%= @city.name %>.</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Get city data using either the database or mock data
  defp get_city_data(slug) do
    # Try to get the city from the database first
    case Locations.get_city_by_slug(slug) do
      %{} = city ->
        # If found, format the data for display
        {:ok, %{
          id: city.id,
          name: city.name,
          slug: city.slug,
          country_name: city.country.name,
          venue_count: get_venue_count_for_city(city.id),
          image_url: get_city_image(city.name)
        }}

      nil ->
        # If not found in database, try mock data
        case get_mock_city_by_slug(slug) do
          nil -> {:error, :not_found}
          city_data -> {:ok, city_data}
        end
    end
  end

  # Get mock city data by slug (for development only)
  defp get_mock_city_by_slug(slug) do
    mock_cities = [
      %{
        id: "1",
        name: "London",
        slug: "london",
        country_name: "United Kingdom",
        venue_count: 120,
        image_url: "https://images.unsplash.com/photo-1533929736458-ca588d08c8be?q=80&w=2000"
      },
      %{
        id: "2",
        name: "New York",
        slug: "new-york",
        country_name: "United States",
        venue_count: 87,
        image_url: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?q=80&w=2000"
      },
      %{
        id: "3",
        name: "Sydney",
        slug: "sydney",
        country_name: "Australia",
        venue_count: 45,
        image_url: "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?q=80&w=2000"
      }
    ]

    Enum.find(mock_cities, fn city -> city.slug == slug end)
  end

  # Count venues for a city (replace with real DB query)
  defp get_venue_count_for_city(city_id) do
    # Replace this with a real database count query in production
    case city_id do
      "1" -> 120
      "2" -> 87
      "3" -> 45
      _ ->
        # If we have real data, try to count real venues
        try do
          Locations.count_venues_by_city_id(city_id)
        rescue
          _ -> 0
        end
    end
  end

  # Get a city image URL from Unsplash service or use a fallback
  defp get_city_image(name) do
    try do
      # Try to get a cached/fetched image from the Unsplash service
      UnsplashService.get_city_image(name)
    rescue
      # If the service is not yet started or there's any other error, use hardcoded fallbacks
      e ->
        Logger.error("Error fetching Unsplash image: #{inspect(e)}")
        case name do
          "London" -> "https://images.unsplash.com/photo-1533929736458-ca588d08c8be?q=80&w=2000"
          "New York" -> "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?q=80&w=2000"
          "Sydney" -> "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?q=80&w=2000"
          _ -> "https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?q=80&w=2000" # Default urban image
        end
    end
  end

  # Get venues for a city (currently using mock data)
  defp get_venues_for_city(_city_id) do
    # This would normally come from your database
    # For now, we'll use mock data
    [
      %{
        id: "1",
        name: "The Crown & Anchor",
        address: "123 Main St, London",
        day_of_week: 2,
        start_time: "8:00 PM",
        entry_fee: "£2",
        description: "A traditional pub quiz with a mix of general knowledge, music, and picture rounds. Prizes include bar tabs and merchandise.",
        hero_image_url: "https://images.unsplash.com/photo-1546726747-421c6d69c929?q=80&w=600",
        rating: 4.7
      },
      %{
        id: "2",
        name: "The Shakespeare",
        address: "456 High St, London",
        day_of_week: 3,
        start_time: "7:30 PM",
        entry_fee: "Free",
        description: "Our Wednesday night quiz is popular with locals and visitors alike. Five rounds of trivia with bonus rounds throughout.",
        hero_image_url: "https://images.unsplash.com/photo-1572116469696-31de0f17cc34?q=80&w=600",
        rating: 4.5
      },
      %{
        id: "3",
        name: "The Red Lion",
        address: "789 Park Ln, London",
        day_of_week: 4,
        start_time: "8:30 PM",
        entry_fee: "£3",
        description: "A challenging quiz night featuring specialized rounds each week. Teams of up to 6 people allowed.",
        hero_image_url: "https://images.unsplash.com/photo-1575444758702-4a6b9222336e?q=80&w=600",
        rating: 4.8
      }
    ]
  end

  defp format_day(day) do
    case day do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Unknown"
    end
  end
end

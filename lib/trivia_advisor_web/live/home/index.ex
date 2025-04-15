defmodule TriviaAdvisorWeb.HomeLive.Index do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisorWeb.Components.UI.{CitySearch, VenueCard, CityCard}

  @impl true
  def mount(_params, _session, socket) do
    # Use real data with caching
    featured_venues = TriviaAdvisor.Locations.get_featured_venues(limit: 4)
    popular_cities = TriviaAdvisor.Locations.get_popular_cities(limit: 6, diverse_countries: true)

    {:ok, assign(socket,
      page_title: "QuizAdvisor - Find the Best Pub Quizzes Near You",
      featured_venues: featured_venues,
      popular_cities: popular_cities
    )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  @impl true
  def handle_info({:city_selected, city}, socket) do
    # In a real app, you would redirect to the city page
    IO.inspect(city, label: "Selected city")

    # Redirect to city page using slug
    # If city has a slug field, use it; otherwise generate a slug from the name
    city_slug = Map.get(city, :slug) ||
                String.downcase(city.name) |> String.replace(~r/[^a-z0-9]+/, "-")

    {:noreply, push_navigate(socket, to: ~p"/cities/#{city_slug}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Hero Section -->
      <section class="bg-gradient-to-r from-indigo-700 to-indigo-900 py-24 text-white">
        <div class="container mx-auto px-6 sm:px-8 md:px-12 lg:px-16 xl:px-20">
          <div class="mx-auto max-w-4xl text-center">
            <h1 class="mb-6 text-4xl font-bold leading-tight sm:text-5xl md:text-6xl">
              Find the Best Pub Quizzes Near You
            </h1>
            <p class="mb-8 text-lg text-indigo-100 md:text-xl">
              Discover and track trivia nights at pubs and venues in your area
            </p>
            <div class="mx-auto max-w-2xl">
              <.live_component module={CitySearch} id="city-search" />
            </div>
          </div>
        </div>
        <div class="absolute inset-0 -z-10 overflow-hidden">
          <svg
            class="absolute bottom-0 left-0 right-0 h-20 w-full text-white"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 1200 120"
            preserveAspectRatio="none"
          >
            <path
              d="M0,0V46.29c47.79,22.2,103.59,32.17,158,28,70.36-5.37,136.33-33.31,206.8-37.5C438.64,32.43,512.34,53.67,583,72.05c69.27,18,138.3,24.88,209.4,13.08,36.15-6,69.85-17.84,104.45-29.34C989.49,25,1113-14.29,1200,52.47V0Z"
              fill="currentColor"
              opacity=".25"
            ></path>
            <path
              d="M0,0V15.81C13,36.92,27.64,56.86,47.69,72.05,99.41,111.27,165,111,224.58,91.58c31.15-10.15,60.09-26.07,89.67-39.8,40.92-19,84.73-46,130.83-49.67,36.26-2.85,70.9,9.42,98.6,31.56,31.77,25.39,62.32,62,103.63,73,40.44,10.79,81.35-6.69,119.13-24.28s75.16-39,116.92-43.05c59.73-5.85,113.28,22.88,168.9,38.84,30.2,8.66,59,6.17,87.09-7.5,22.43-10.89,48-26.93,60.65-49.24V0Z"
              fill="currentColor"
              opacity=".5"
            ></path>
            <path
              d="M0,0V5.63C149.93,59,314.09,71.32,475.83,42.57c43-7.64,84.23-20.12,127.61-26.46,59-8.63,112.48,12.24,165.56,35.4C827.93,77.22,886,95.24,951.2,90c86.53-7,172.46-45.71,248.8-84.81V0Z"
              fill="currentColor"
            ></path>
          </svg>
        </div>
      </section>

      <!-- How It Works Section -->
      <section class="bg-white py-16">
        <div class="container mx-auto px-6 sm:px-8 md:px-12 lg:px-16 xl:px-20">
          <h2 class="mb-12 text-center text-3xl font-bold tracking-tight text-gray-900">How QuizAdvisor Works</h2>
          <div class="grid gap-8 md:grid-cols-3">
            <div class="flex flex-col items-center text-center">
              <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-indigo-100 text-indigo-600">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-8 w-8">
                  <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z" />
                </svg>
              </div>
              <h3 class="mb-2 text-xl font-semibold">Find Quiz Nights</h3>
              <p class="text-gray-600">Discover pub quizzes and trivia events in your area or any city you're visiting.</p>
            </div>
            <div class="flex flex-col items-center text-center">
              <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-indigo-100 text-indigo-600">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-8 w-8">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5m-9-6h.008v.008H12v-.008ZM12 15h.008v.008H12V15Zm0 2.25h.008v.008H12v-.008ZM9.75 15h.008v.008H9.75V15Zm0 2.25h.008v.008H9.75v-.008ZM7.5 15h.008v.008H7.5V15Zm0 2.25h.008v.008H7.5v-.008Zm6.75-4.5h.008v.008h-.008v-.008Zm0 2.25h.008v.008h-.008V15Zm0 2.25h.008v.008h-.008v-.008Zm2.25-4.5h.008v.008H16.5v-.008Zm0 2.25h.008v.008H16.5V15Z" />
                </svg>
              </div>
              <h3 class="mb-2 text-xl font-semibold">Attend Events</h3>
              <p class="text-gray-600">Join fun trivia nights and test your knowledge across various topics.</p>
            </div>
            <div class="flex flex-col items-center text-center">
              <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-indigo-100 text-indigo-600">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-8 w-8">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z" />
                </svg>
              </div>
              <h3 class="mb-2 text-xl font-semibold">Rate & Review</h3>
              <p class="text-gray-600">Share your experience and help others find the best trivia nights.</p>
            </div>
          </div>
        </div>
      </section>

      <!-- Featured Venues Section -->
      <section class="bg-gray-50 py-16">
        <div class="container mx-auto px-6 sm:px-8 md:px-12 lg:px-16 xl:px-20">
          <div class="mb-8 flex items-center justify-between">
            <h2 class="text-3xl font-bold tracking-tight text-gray-900">Latest Venues</h2>
            <a href={~p"/venues/latest"} class="text-sm font-medium text-indigo-600 hover:text-indigo-700">
              View all new venues
              <span aria-hidden="true">→</span>
            </a>
          </div>
          <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4" data-testid="featured-venues">
            <%= for venue <- @featured_venues do %>
              <VenueCard.venue_card venue={venue} />
            <% end %>
          </div>
        </div>
      </section>

      <!-- Popular Cities Section -->
      <section class="bg-white py-16">
        <div class="container mx-auto px-6 sm:px-8 md:px-12 lg:px-16 xl:px-20">
          <div class="mb-8 flex items-center justify-between">
            <h2 class="text-3xl font-bold tracking-tight text-gray-900">Popular Cities</h2>
            <a href={~p"/cities"} class="text-sm font-medium text-indigo-600 hover:text-indigo-700">
              View all cities
              <span aria-hidden="true">→</span>
            </a>
          </div>
          <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3" data-testid="popular-cities">
            <%= for city <- @popular_cities do %>
              <CityCard.city_card city={city} />
            <% end %>
          </div>
        </div>
      </section>

      <!-- Newsletter Section -->
      <section class="bg-white py-16">
        <div class="container mx-auto px-6 sm:px-8 md:px-12 lg:px-16 xl:px-20">
          <div class="rounded-2xl bg-indigo-700 px-6 py-12 md:py-16 md:px-12">
            <div class="mx-auto max-w-3xl text-center">
              <h2 class="text-3xl font-bold tracking-tight text-white sm:text-4xl">
                Get weekly trivia updates in your area
              </h2>
              <p class="mt-4 text-lg text-indigo-100">
                Stay in the loop with new quiz nights and events. We'll send you the best trivia events nearby.
              </p>
              <div class="mt-8 flex items-center justify-center">
                <form class="flex w-full max-w-md flex-col gap-2 sm:flex-row">
                  <div class="relative flex-grow rounded-md shadow-sm">
                    <input
                      type="email"
                      name="email"
                      id="email"
                      class="block w-full rounded-md border-0 py-3 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-500 sm:text-sm"
                      placeholder="Enter your email"
                    />
                  </div>
                  <button
                    type="submit"
                    class="rounded-md bg-white px-4 py-3 text-sm font-semibold text-indigo-600 shadow-sm hover:bg-indigo-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
                  >
                    Subscribe
                  </button>
                </form>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Map Preview Section -->
      <section class="bg-gray-50 py-16">
        <div class="container mx-auto px-6 sm:px-8 md:px-12 lg:px-16 xl:px-20">
          <div class="grid gap-8 md:grid-cols-2">
            <div class="flex flex-col justify-center">
              <h2 class="mb-4 text-3xl font-bold tracking-tight text-gray-900">Find Trivia Nights on the Map</h2>
              <p class="mb-6 text-lg text-gray-600">
                Easily discover trivia venues near you or in any area you're interested in visiting. Our interactive map makes finding your next quiz night simple.
              </p>
              <div>
                <a href="#" class="inline-flex items-center justify-center rounded-md bg-indigo-600 px-5 py-3 text-base font-medium text-white hover:bg-indigo-700">
                  Open Map View
                </a>
              </div>
            </div>
            <div class="overflow-hidden rounded-lg shadow-md">
              <div class="aspect-w-16 aspect-h-9 h-full w-full bg-gray-200">
                <!-- Placeholder for map -->
                <div class="flex h-full w-full items-center justify-center">
                  <p class="text-gray-500">Interactive Map Preview</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end
end

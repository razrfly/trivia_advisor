defmodule TriviaAdvisorWeb.CountryLive.Show do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisor.Locations
  alias TriviaAdvisorWeb.Components.UI.CityCard
  alias TriviaAdvisor.Services.UnsplashService
  require Logger

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case get_country_data(slug) do
      {:ok, country_data} ->
        socket = socket
          |> assign(:page_title, "#{country_data.name} - Cities and Trivia Venues")
          |> assign(:country, country_data)
          |> assign(:cities, get_cities_by_country(country_data.country))

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> assign(:page_title, "Country Not Found")
         |> assign(:country, %{
           id: nil,
           name: "Unknown Country",
           code: nil,
           image_url: nil
         })
         |> assign(:cities, [])}
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
      <!-- Country Hero Section -->
      <div class="relative">
        <div class="h-64 overflow-hidden sm:h-80 lg:h-96">
          <img
            src={@country.image_url || "https://placehold.co/1200x400?text=#{@country.name}"}
            alt={@country.name}
            class="h-full w-full object-cover"
          />
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent"></div>
        <div class="absolute bottom-0 w-full px-4 py-8 text-white sm:px-6 lg:px-8">
          <div class="container mx-auto">
            <h1 class="text-4xl font-bold"><%= @country.name %></h1>
            <p class="mt-2 text-lg"><%= length(@cities) %> Cities with Trivia Venues</p>
            <%= if @country.attribution do %>
              <p class="mt-1 text-xs opacity-80">
                Photo by <a href={@country.attribution.photographer_url} target="_blank" rel="noopener" class="hover:underline"><%= @country.attribution.photographer_name %></a>
                on <a href={@country.attribution.unsplash_url} target="_blank" rel="noopener" class="hover:underline">Unsplash</a>
              </p>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="container mx-auto px-4 py-12 sm:px-6 lg:px-8">
        <%= if Enum.empty?(@cities) do %>
          <div class="my-16 text-center">
            <h2 class="text-2xl font-semibold text-gray-900">No cities found in <%= @country.name %></h2>
            <p class="mt-2 text-gray-600">We don't have any trivia venues in this country yet.</p>
          </div>
        <% else %>
          <div class="mb-8">
            <h2 class="text-2xl font-bold text-gray-900">Cities in <%= @country.name %></h2>
            <p class="mt-2 text-gray-600">
              Explore cities with trivia venues in <%= @country.name %>
            </p>
          </div>

          <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <%= for city <- @cities do %>
              <CityCard.city_card city={city} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_country_data(slug) do
    case Locations.get_country_by_slug(slug) do
      nil ->
        {:error, :not_found}

      country ->
        # Get the country's image using UnsplashService with better search terms and attribution
        image_data = UnsplashService.get_country_image(country.name)

        # Build the country data structure
        {:ok, %{
          id: country.id,
          name: country.name,
          code: country.code,
          country: country,  # Include the full country struct for future use
          image_url: image_data.url,
          attribution: image_data.attribution
        }}
    end
  end

  defp get_cities_by_country(country) do
    # Get cities for this country and include venue counts
    cities = Locations.list_cities_by_country_with_venue_counts(country.id)

    # Get city names for batch image fetching
    city_names = Enum.map(cities, & &1.name)

    # Batch fetch images for all cities
    city_images = UnsplashService.get_city_images_batch(city_names)

    # Sort cities by venue count in descending order
    Enum.sort_by(cities, & &1.venue_count, :desc)
    |> Enum.map(fn city ->
      # Transform each city to match the format expected by the CityCard component
      # Get image from pre-fetched batch
      image_url = Map.get(city_images, city.name)

      %{
        id: city.id,
        name: city.name,
        country_name: country.name,
        venue_count: city.venue_count,
        image_url: image_url,
        slug: city.slug
      }
    end)
  end
end

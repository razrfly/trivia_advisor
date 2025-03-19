defmodule TriviaAdvisorWeb.CityLive.Show do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Services.UnsplashService
  alias TriviaAdvisorWeb.Helpers.FormatHelpers
  alias TriviaAdvisorWeb.Helpers.LocalizationHelpers
  require Logger
  import FormatHelpers, only: [
    time_ago: 1,
    format_day_of_week: 1,
    get_event_source_data: 1
  ]

  @radius_options [
    {"5 km", 5},
    {"10 km", 10},
    {"25 km", 25},
    {"50 km", 50}
  ]
  @default_radius 25

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Fetch the city by slug
    case get_city_data(slug) do
      {:ok, city_data} ->
        socket = socket
          |> assign(:page_title, "#{city_data.name} - Trivia Venues")
          |> assign(:city, city_data)
          |> assign(:radius, @default_radius)
          |> assign(:radius_options, @radius_options)
          |> assign(:selected_suburbs, [])
          |> assign(:suburbs, get_suburbs(city_data.city))

        # Get venues for the city using spatial search
        {:ok, assign(socket, :venues, get_venues_near_city(city_data.city, @default_radius))}

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
         |> assign(:venues, [])
         |> assign(:radius, @default_radius)
         |> assign(:radius_options, @radius_options)
         |> assign(:selected_suburbs, [])
         |> assign(:suburbs, [])}
    end
  end

  @impl true
  def handle_params(%{"slug" => slug}, _, socket) do
    {:noreply,
     socket
     |> assign(:slug, slug)}
  end

  @impl true
  def handle_event("change-radius", %{"radius" => radius}, socket) do
    radius = String.to_integer(radius)

    # Update venues with new radius
    venues = get_venues_near_city(socket.assigns.city.city, radius)

    {:noreply, socket
      |> assign(:radius, radius)
      |> assign(:venues, venues)}
  end

  @impl true
  def handle_event("select-suburb", %{"suburb-id" => suburb_id}, socket) do
    suburb_id = String.to_integer(suburb_id)

    # Find the selected suburb data from the suburbs list
    suburb = Enum.find(socket.assigns.suburbs, fn %{city: city} -> city.id == suburb_id end)

    # Only proceed if the suburb exists and is not already selected
    if suburb && suburb_id not in socket.assigns.selected_suburbs do
      selected_suburbs = [suburb_id | socket.assigns.selected_suburbs]

      # Filter venues based on selected suburbs
      venues = filter_venues_by_suburbs(
        socket.assigns.city.city,
        socket.assigns.radius,
        selected_suburbs,
        socket.assigns.suburbs
      )

      {:noreply, socket
        |> assign(:selected_suburbs, selected_suburbs)
        |> assign(:venues, venues)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove-suburb", %{"suburb-id" => suburb_id}, socket) do
    suburb_id = String.to_integer(suburb_id)

    # Remove the suburb from the selected list
    selected_suburbs = Enum.reject(socket.assigns.selected_suburbs, fn id -> id == suburb_id end)

    # If no suburbs are selected, show all venues within radius
    # Otherwise, filter venues based on remaining selected suburbs
    venues = if Enum.empty?(selected_suburbs) do
      get_venues_near_city(socket.assigns.city.city, socket.assigns.radius)
    else
      filter_venues_by_suburbs(
        socket.assigns.city.city,
        socket.assigns.radius,
        selected_suburbs,
        socket.assigns.suburbs
      )
    end

    {:noreply, socket
      |> assign(:selected_suburbs, selected_suburbs)
      |> assign(:venues, venues)}
  end

  @impl true
  def handle_event("clear-suburbs", _params, socket) do
    # Clear all suburb filters and show all venues within radius
    venues = get_venues_near_city(socket.assigns.city.city, socket.assigns.radius)

    {:noreply, socket
      |> assign(:selected_suburbs, [])
      |> assign(:venues, venues)}
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
        <div class="absolute bottom-0 w-full px-4 py-8 text-white sm:px-6 lg:px-8">
          <div class="container mx-auto">
            <h1 class="text-4xl font-bold"><%= @city.name %>, <%= @city.country_name %></h1>
            <p class="mt-2 text-lg"><%= @city.venue_count %> Trivia Venues</p>
            <%= if @city.attribution do %>
              <p class="mt-1 text-xs opacity-80">
                Photo by
                <%= if Map.get(@city.attribution, "photographer_url") do %>
                  <a href={Map.get(@city.attribution, :photographer_url) || Map.get(@city.attribution, "photographer_url")} target="_blank" rel="noopener" class="hover:underline">
                    <%= Map.get(@city.attribution, :photographer_name) || Map.get(@city.attribution, "photographer_name") %>
                  </a>
                <% else %>
                  <%= Map.get(@city.attribution, :photographer_name) || Map.get(@city.attribution, "photographer_name") %>
                <% end %>
                <%= if Map.get(@city.attribution, :unsplash_url) || Map.get(@city.attribution, "unsplash_url") do %>
                  on <a href={Map.get(@city.attribution, :unsplash_url) || Map.get(@city.attribution, "unsplash_url")} target="_blank" rel="noopener" class="hover:underline">Unsplash</a>
                <% end %>
              </p>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <!-- Filters -->
        <div class="mb-8 flex flex-wrap items-center justify-between gap-4">
          <h2 class="text-2xl font-bold text-gray-900">Trivia Venues in <%= @city.name %></h2>

          <div class="flex items-center gap-3">
            <label for="radius" class="text-sm font-medium text-gray-700">Search radius:</label>
            <form phx-change="change-radius" class="flex items-center">
              <select
                id="radius"
                name="radius"
                class="rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
                value={@radius}
              >
                <%= for {label, value} <- @radius_options do %>
                  <option value={value} selected={value == @radius}><%= label %></option>
                <% end %>
              </select>
            </form>
          </div>
        </div>

        <p class="mb-4 text-lg text-gray-600">
          Discover the best pub quizzes and trivia nights near <%= @city.name %>.
          <%= if @radius != 0 do %>
            Showing venues within <%= @radius %> km.
          <% end %>
        </p>

        <%= if length(@suburbs) > 0 do %>
          <div class="mb-6">
            <div class="flex justify-between items-center mb-3">
              <h3 class="text-sm font-medium text-gray-700">Filter by suburb:</h3>
              <%= if length(@selected_suburbs) > 0 do %>
                <button
                  phx-click="clear-suburbs"
                  class="text-sm text-indigo-600 hover:text-indigo-800"
                >
                  Clear filters
                </button>
              <% end %>
            </div>

            <div class="flex flex-wrap gap-2">
              <%= for suburb <- @suburbs do %>
                <% is_selected = suburb.city.id in @selected_suburbs %>
                <%= if is_selected do %>
                  <button
                    phx-click="remove-suburb"
                    phx-value-suburb-id={suburb.city.id}
                    class="inline-flex items-center rounded-full bg-indigo-100 py-1.5 pl-3 pr-2 text-sm font-medium text-indigo-700 hover:bg-indigo-200"
                  >
                    <%= suburb.city.name %> (<%= suburb.venue_count %>)
                    <span class="ml-1 inline-flex h-4 w-4 flex-shrink-0 items-center justify-center rounded-full text-indigo-500 hover:bg-indigo-200 hover:text-indigo-600">
                      <svg class="h-2.5 w-2.5" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
                        <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z"></path>
                      </svg>
                    </span>
                  </button>
                <% else %>
                  <button
                    phx-click="select-suburb"
                    phx-value-suburb-id={suburb.city.id}
                    class="inline-flex items-center rounded-full bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-800 hover:bg-gray-200"
                  >
                    <%= suburb.city.name %> (<%= suburb.venue_count %>)
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if length(@venues) > 0 do %>
          <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
            <%= for venue_data <- @venues do %>
              <% venue = venue_data.venue %>
              <div class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm transition hover:shadow">
                <div class="relative h-48">
                  <a href={~p"/venues/#{venue.slug}"}>
                    <img
                      src={venue.hero_image_url || get_venue_image(venue)}
                      alt={venue.name}
                      class="h-full w-full object-cover"
                    />
                  </a>
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
                  <a href={~p"/venues/#{venue.slug}"} class="hover:text-indigo-600">
                    <h3 class="mb-1 text-lg font-bold text-gray-900"><%= venue.name %></h3>
                  </a>
                  <p class="mb-2 text-sm text-gray-600">
                    <%= venue.address %>
                    <span class="mt-1 block text-xs font-medium text-indigo-600">
                      <%= Float.round(venue_data.distance_km, 1) %> km from city center
                    </span>
                  </p>
                  <div class="mb-3 flex items-center text-sm text-gray-600">
                    <span class="font-medium text-indigo-600"><%= format_day(get_venue_day_of_week(venue)) %>s</span>
                    <span class="mx-2">•</span>
                    <span><%= get_venue_start_time(venue) %></span>
                    <span class="mx-2">•</span>
                    <span><%= get_venue_entry_fee(venue) %></span>
                  </div>
                  <p class="mb-4 text-sm text-gray-600 line-clamp-3"><%= get_venue_description(venue) %></p>

                  <%= if venue.last_seen_at do %>
                    <div class="flex items-center mt-2 mb-2 text-xs text-gray-500">
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-1">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                      </svg>
                      <span>Updated <%= time_ago(venue.last_seen_at) %></span>
                      <%= if venue.source_name do %>
                        <span class="mx-1">•</span>
                        <span>Source:
                          <%= if venue.source_url do %>
                            <a href={venue.source_url} target="_blank" class="text-indigo-600 hover:text-indigo-800"><%= venue.source_name %></a>
                          <% else %>
                            <%= venue.source_name %>
                          <% end %>
                        </span>
                      <% end %>
                    </div>
                  <% end %>

                  <a
                    href={~p"/venues/#{venue.slug}"}
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
    """
  end

  # Get venues near a city using spatial search
  defp get_venues_near_city(city, radius) do
    try do
      # Get venues near the city within the specified radius
      results = Locations.find_venues_near_city(city, radius_km: radius, load_relations: true)

      # Filter out venues without events
      results_with_events = Enum.filter(results, fn %{venue: venue} ->
        venue.events && Enum.any?(venue.events)
      end)

      # Format the venue data for display
      Enum.map(results_with_events, fn %{venue: venue, distance_km: distance} ->
        try do
          # Extract event source data if available
          event_source_data = get_event_source_data(venue)

          # Ensure we have country data for currency detection
          venue_with_country = ensure_country_data(venue, city)

          %{
            venue: %{
              id: venue.id,
              name: venue.name,
              slug: venue.slug,
              address: venue.address,
              description: get_venue_description(venue),
              hero_image_url: get_venue_image(venue),
              rating: get_venue_rating(venue),
              events: Map.get(venue, :events, []),
              last_seen_at: event_source_data[:last_seen_at],
              source_name: event_source_data[:source_name],
              source_url: event_source_data[:source_url],
              # Add country_code to venue for currency detection
              country_code: get_country(venue_with_country).code
            },
            distance_km: distance
          }
        rescue
          e ->
            Logger.error("Error processing venue data: #{inspect(e)}")
            # Return a simplified venue object with just the essential data
            %{
              venue: %{
                id: venue.id,
                name: venue.name,
                slug: venue.slug,
                address: venue.address || "No address available",
                description: "Information for this venue is temporarily unavailable.",
                hero_image_url: "/images/default-venue.jpg",
                rating: 4.0,
                events: [],
                last_seen_at: nil,
                source_name: nil,
                source_url: nil,
                # Add country_code from the parent city for proper currency formatting
                country_code: city.country.code
              },
              distance_km: distance
            }
        end
      end)
    rescue
      e ->
        Logger.error("Error fetching venues for city: #{inspect(e)}")
        # Return empty list on error
        []
    end
  end

  # Get city data using either the database or mock data
  defp get_city_data(slug) do
    # Try to get the city from the database first
    case Locations.get_city_by_slug(slug) do
      %{} = city ->
        # If found, format the data for display
        # Use count_venues_with_events_near_city to only count venues with events
        venues_count = Locations.count_venues_with_events_near_city(city, radius_km: 50)

        # Get the image data from the city's unsplash_gallery
        {image_url, attribution} = get_image_data_from_gallery(city)

        {:ok, %{
          id: city.id,
          name: city.name,
          slug: city.slug,
          country_name: city.country.name,
          venue_count: venues_count,
          image_url: image_url,
          attribution: attribution,
          city: city
        }}

      nil ->
        # If not found in database, try mock data
        case get_mock_city_by_slug(slug) do
          nil -> {:error, :not_found}
          city_data -> {:ok, city_data}
        end
    end
  end

  # Extract image data from the city's unsplash_gallery
  defp get_image_data_from_gallery(city) do
    # Default image URL if none is found
    default_image_url = "/images/default_city.jpg"

    if city.unsplash_gallery &&
       is_map(city.unsplash_gallery) &&
       Map.has_key?(city.unsplash_gallery, "images") &&
       is_list(city.unsplash_gallery["images"]) &&
       length(city.unsplash_gallery["images"]) > 0 do

      # Get the current index or default to 0
      current_index = Map.get(city.unsplash_gallery, "current_index", 0)

      # Get the current image safely
      current_image = Enum.at(city.unsplash_gallery["images"], current_index) || List.first(city.unsplash_gallery["images"])

      if current_image && Map.has_key?(current_image, "url") do
        # Extract the image URL
        image_url = current_image["url"]

        # Extract attribution
        attribution = if Map.has_key?(current_image, "attribution") do
          current_image["attribution"]
        else
          %{"photographer_name" => "Photographer", "photographer_url" => nil, "unsplash_url" => "https://unsplash.com"}
        end

        {image_url, attribution}
      else
        # Fallback to default if no URL in the gallery
        {default_image_url, %{"photographer_name" => "Default Image"}}
      end
    else
      # If no gallery or no images, use fallback hardcoded image URL
      image_url = get_city_image(city.name)
      {image_url, %{"photographer_name" => "Unsplash", "unsplash_url" => "https://unsplash.com"}}
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
        image_url: "https://images.unsplash.com/photo-1533929736458-ca588d08c8be?q=80&w=2000",
        attribution: %{
          "photographer_name" => "Benjamin Davies",
          "photographer_url" => "https://unsplash.com/@bendavisual",
          "unsplash_url" => "https://unsplash.com/photos/Oja2ty_9ZLM"
        }
      },
      %{
        id: "2",
        name: "New York",
        slug: "new-york",
        country_name: "United States",
        venue_count: 87,
        image_url: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?q=80&w=2000",
        attribution: %{
          "photographer_name" => "Luca Bravo",
          "photographer_url" => "https://unsplash.com/@lucabravo",
          "unsplash_url" => "https://unsplash.com/photos/ESkw2ayO2As"
        }
      },
      %{
        id: "3",
        name: "Sydney",
        slug: "sydney",
        country_name: "Australia",
        venue_count: 65,
        image_url: "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?q=80&w=2000",
        attribution: %{
          "photographer_name" => "Dan Freeman",
          "photographer_url" => "https://unsplash.com/@danfreemanphoto",
          "unsplash_url" => "https://unsplash.com/photos/7Zb7kUyQg1E"
        }
      },
      %{
        id: "4",
        name: "Melbourne",
        slug: "melbourne",
        country_name: "Australia",
        venue_count: 54,
        image_url: "https://images.unsplash.com/photo-1545044846-351ba102b6d5?q=80&w=2000",
        attribution: %{
          "photographer_name" => "Weyne Yew",
          "photographer_url" => "https://unsplash.com/@weyneyew",
          "unsplash_url" => "https://unsplash.com/photos/D4YrzSwyIFQ"
        }
      }
    ]

    Enum.find(mock_cities, fn city -> city.slug == slug end)
  end

  # Extract day of week from venue
  defp get_venue_day_of_week(venue) do
    # Get the day of week from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :day_of_week, 1) # Default to Monday if not found
    else
      # Default value if no events
      1 # Monday as default
    end
  end

  # Extract start time from venue
  defp get_venue_start_time(venue) do
    # Get the start time from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      # Since start_time is required in the schema, no fallback needed
      time = event.start_time

      # Get country data for proper localization
      country = get_venue_country(venue)

      # Use localization helper to format the time
      LocalizationHelpers.format_localized_time(time, country)
    else
      # Default value if no events - use localized 7:00 PM
      default_time = ~T[19:00:00]
      country = get_venue_country(venue)
      LocalizationHelpers.format_localized_time(default_time, country)
    end
  end

  # Helper to get country data for a venue
  defp get_venue_country(venue) do
    cond do
      # First check for direct country_code field (which is what we use in the city index)
      is_map(venue) && Map.has_key?(venue, :country_code) && venue.country_code ->
        %{code: venue.country_code}

      # If venue has loaded city with country association
      is_map(venue) && Map.has_key?(venue, :city) &&
      !is_nil(venue.city) && !is_struct(venue.city, Ecto.Association.NotLoaded) &&
      Map.has_key?(venue.city, :country) &&
      !is_nil(venue.city.country) && !is_struct(venue.city.country, Ecto.Association.NotLoaded) ->
        venue.city.country

      # Try to get country code from metadata
      is_map(venue) && Map.has_key?(venue, :metadata) && is_map(venue.metadata) &&
      Map.has_key?(venue.metadata, "country_code") ->
        %{code: venue.metadata["country_code"]}

      # Default to US
      true ->
        %{code: "US"}
    end
  end

  # Extract entry fee from venue
  defp get_venue_entry_fee(venue) do
    # Get the entry fee from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      fee_cents = Map.get(event, :entry_fee_cents)

      if fee_cents do
        # Format the currency using the same approach as venue show page
        format_currency(fee_cents, get_country_currency(venue))
      else
        # Free if no fee specified
        "Free"
      end
    else
      # Default value if no events
      "Free"
    end
  end

  # Helper to get country's currency code
  defp get_country_currency(venue) do
    country = get_country(venue)

    cond do
      # Check if currency code is stored in country data
      country && Map.has_key?(country, :currency_code) && country.currency_code ->
        country.currency_code
      # Use Countries library to get currency code if we have a country code
      country && country.code ->
        country_data = Countries.get(country.code)
        if country_data && Map.has_key?(country_data, :currency_code), do: country_data.currency_code, else: "USD"
      # Default to USD if we don't know
      true ->
        "USD"
    end
  end

  # Helper to get country information
  defp get_country(venue) do
    # First check if venue has a direct country_code
    if Map.has_key?(venue, :country_code) do
      %{code: venue.country_code, name: "Unknown", slug: "unknown"}
    else
      # Try to safely extract country from city if it exists
      try do
        if Map.has_key?(venue, :city) &&
           !is_nil(venue.city) &&
           !is_struct(venue.city, Ecto.Association.NotLoaded) &&
           Map.has_key?(venue.city, :country) &&
           !is_nil(venue.city.country) &&
           !is_struct(venue.city.country, Ecto.Association.NotLoaded) do
          venue.city.country
        else
          # Default fallback
          %{code: "US", name: "Unknown", slug: "unknown"}
        end
      rescue
        # If any error occurs, return a default
        _ -> %{code: "US", name: "Unknown", slug: "unknown"}
      end
    end
  end

  # Helper to format currency with proper symbol and localization
  defp format_currency(amount_cents, currency_code) when is_number(amount_cents) do
    # Create Money struct with proper currency
    money = Money.new(amount_cents, currency_code)

    # Let the Money library handle the formatting
    Money.to_string(money)
  end
  defp format_currency(_, _), do: "Free"

  # Extract description from venue
  defp get_venue_description(venue) do
    # First try to get description from events
    event_description = if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :description)
    end

    # Use direct description if available, then try event description, then metadata, then fallback to generic
    event_description ||
    Map.get(venue, :description) ||
    (if Map.has_key?(venue, :metadata), do: venue.metadata["description"]) ||
    "A trivia night at #{venue.name}. Join us for a fun evening of questions, prizes, and drinks."
  end

  # Get a venue image URL
  defp get_venue_image(venue) do
    try do
      # First try to get an image from the venue's events (most events should have hero images)
      event_image = if is_map(venue) && Map.get(venue, :events) && is_list(venue.events) && Enum.any?(venue.events) do
        # Find first event with a hero image
        venue.events
        |> Enum.find_value(fn event ->
          if is_map(event) && event.hero_image && is_map(event.hero_image) && event.hero_image.file_name do
            try do
              # First try Waffle's URL generation
              waffle_result = try do
                # Manually ensure venue is associated
                event_with_venue = if (is_nil(Map.get(event, :venue)) || is_struct(Map.get(event, :venue), Ecto.Association.NotLoaded)) && Map.has_key?(venue, :id) do
                  Map.put(event, :venue, venue)
                else
                  event
                end

                raw_url = TriviaAdvisor.Uploaders.HeroImage.url({event.hero_image, event_with_venue})
                Logger.debug("Raw hero image URL: #{inspect(raw_url)}")

                if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
                  # Get bucket name from env var, with fallback
                  bucket = System.get_env("BUCKET_NAME") ||
                           Application.get_env(:waffle, :bucket) ||
                           "trivia-advisor"

                  # Get S3 configuration
                  s3_config = Application.get_env(:ex_aws, :s3, [])
                  host = case s3_config[:host] do
                    h when is_binary(h) -> h
                    _ -> "fly.storage.tigris.dev"
                  end

                  # Format path correctly for S3 (remove leading slash)
                  s3_path = if String.starts_with?(raw_url, "/"), do: String.slice(raw_url, 1..-1//1), else: raw_url

                  # Construct the full S3 URL using virtual host style
                  full_url = "https://#{bucket}.#{host}/#{s3_path}"
                  Logger.debug("Constructed S3 URL from Waffle: #{full_url}")
                  {:ok, full_url}
                else
                  # In development, use the standard approach
                  processed_url = String.replace(raw_url, ~r{^/priv/static}, "")
                  {:ok, processed_url}
                end
              rescue
                e ->
                  Logger.error("Error using Waffle URL generation: #{Exception.message(e)}")
                  :error
              end

              case waffle_result do
                {:ok, url} ->
                  url
                _ ->
                  # Fallback to manual URL construction (which we know works)
                  if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
                    # Get bucket name from env var, with fallback
                    bucket = System.get_env("BUCKET_NAME") ||
                             Application.get_env(:waffle, :bucket) ||
                             "trivia-advisor"

                    # Get S3 configuration
                    s3_config = Application.get_env(:ex_aws, :s3, [])
                    host = case s3_config[:host] do
                      h when is_binary(h) -> h
                      _ -> "fly.storage.tigris.dev"
                    end

                    # Get file name parts
                    file_name = event.hero_image.file_name
                    extension = Path.extname(file_name)
                    base_name = Path.basename(file_name, extension)

                    # Construct manual URL like we did in our working solution
                    original_path = "uploads/venues/#{venue.slug}/original_#{base_name}#{extension}"
                    Logger.debug("Fallback to manual S3 URL: https://#{bucket}.#{host}/#{original_path}")
                    "https://#{bucket}.#{host}/#{original_path}"
                  else
                    # In development, try again with standard approach
                    raw_url = TriviaAdvisor.Uploaders.HeroImage.url({event.hero_image, event})
                    String.replace(raw_url, ~r{^/priv/static}, "")
                  end
              end
            rescue
              e ->
                Logger.error("Error processing hero image URL: #{Exception.message(e)}")
                nil
            end
          end
        end)
      end

      # Check for stored Google Place images
      google_place_image = if is_map(venue) && Map.get(venue, :google_place_images) && is_list(venue.google_place_images) && Enum.any?(venue.google_place_images) do
        try do
          TriviaAdvisor.Services.GooglePlaceImageStore.get_first_image_url(venue)
        rescue
          _ -> nil
        end
      end

      # Check for hero_image_url in metadata
      metadata_image = if is_map(venue) && Map.has_key?(venue, :metadata) && is_map(venue.metadata) do
        venue.metadata["hero_image_url"] ||
        venue.metadata["hero_image"] ||
        venue.metadata["image_url"] ||
        venue.metadata["image"]
      end

      # Check if venue has a field for hero_image directly
      venue_image = if is_map(venue) do
        Map.get(venue, :hero_image_url) ||
        Map.get(venue, :hero_image) ||
        Map.get(venue, :image_url) ||
        Map.get(venue, :image)
      end

      # Use the first available image or fall back to placeholder
      image_url = event_image || google_place_image || metadata_image || venue_image
      Logger.debug("Selected image URL: #{inspect(image_url)}")

      if is_binary(image_url) do
        process_image_url(image_url)
      else
        "/images/default-venue.jpg"
      end
    rescue
      e ->
        Logger.error("Error getting venue image: #{inspect(e)}")
        "/images/default-venue.jpg"
    end
  end

  # Helper to process image URLs to ensure they're full URLs
  defp process_image_url(path) do
    # Return a default image if path is nil or not a binary
    if is_nil(path) or not is_binary(path) do
      "/images/default-venue.jpg"
    else
      try do
        cond do
          # Already a full URL
          String.starts_with?(path, "http") ->
            path

          # Check if using S3 storage in production
          Application.get_env(:waffle, :storage) == Waffle.Storage.S3 ->
            # Get S3 configuration
            s3_config = Application.get_env(:ex_aws, :s3, [])
            bucket = Application.get_env(:waffle, :bucket, "trivia-advisor")

            # For Tigris S3-compatible storage, we need to use a public URL pattern
            # that doesn't rely on object ACLs
            host = case s3_config[:host] do
              h when is_binary(h) -> h
              _ -> "fly.storage.tigris.dev"
            end

            # Format path correctly for S3 (remove leading slash)
            s3_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path

            # Construct the full S3 URL
            # Using direct virtual host style URL
            "https://#{bucket}.#{host}/#{s3_path}"

          # Local development
          true ->
            if String.starts_with?(path, "/") do
              "#{TriviaAdvisorWeb.Endpoint.url()}#{path}"
            else
              "#{TriviaAdvisorWeb.Endpoint.url()}/#{path}"
            end
        end
      rescue
        e ->
          Logger.error("Error constructing URL from path #{inspect(path)}: #{Exception.message(e)}")
          "/images/default-venue.jpg"
      end
    end
  end

  # Get a city image URL from Unsplash service or use a fallback
  defp get_city_image(name) when is_binary(name) do
    try do
      # Try to get a cached/fetched image from the Unsplash service
      case UnsplashService.get_city_image(name) do
        {:ok, image_url} when is_binary(image_url) ->
          image_url
        image_url when is_binary(image_url) ->
          image_url
        _ ->
          # If Unsplash service returned nil or an error, use fallback
          get_fallback_city_image(name)
      end
    rescue
      # If the service is not yet started or there's any other error, use hardcoded fallbacks
      e ->
        Logger.error("Error fetching Unsplash image: #{inspect(e)}")
        get_fallback_city_image(name)
    end
  end

  defp get_city_image(_), do: "https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?q=80&w=2000"

  # Helper to get fallback city images based on city name
  defp get_fallback_city_image(name) do
    cond do
      String.contains?(String.downcase(name), "london") ->
        "https://images.unsplash.com/photo-1533929736458-ca588d08c8be?q=80&w=2000"
      String.contains?(String.downcase(name), "new york") ->
        "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?q=80&w=2000"
      String.contains?(String.downcase(name), "sydney") ->
        "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?q=80&w=2000"
      String.contains?(String.downcase(name), "melbourne") ->
        "https://images.unsplash.com/photo-1545044846-351ba102b6d5?q=80&w=2000"
      String.contains?(String.downcase(name), "paris") ->
        "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?q=80&w=2000"
      String.contains?(String.downcase(name), "tokyo") ->
        "https://images.unsplash.com/photo-1503899036084-c55cdd92da26?q=80&w=2000"
      true ->
        "https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?q=80&w=2000" # Default urban image
    end
  end

  # Extract rating from venue
  defp get_venue_rating(venue) do
    # Check for direct rating first, then metadata rating
    cond do
      # Direct rating on venue object
      is_number(Map.get(venue, :rating)) ->
        venue.rating

      # In metadata if it exists
      Map.has_key?(venue, :metadata) ->
        case venue.metadata["rating"] do
          nil ->
            # Generate random rating if not available
            (3.5 + :rand.uniform() * 1.5) |> Float.round(1)
          rating when is_number(rating) ->
            # Use the rating directly if it's a number
            rating
          %{"value" => value} when is_number(value) ->
            # Extract the value from map if it's in that format
            value
          _ ->
            # Fallback for any other format
            (3.5 + :rand.uniform() * 1.5) |> Float.round(1)
        end

      # No rating info available - generate random
      true ->
        (3.5 + :rand.uniform() * 1.5) |> Float.round(1)
    end
  end

  defp format_day(day) do
    format_day_of_week(day)
  end

  # Get suburbs (nearby cities) with venue counts
  defp get_suburbs(city) do
    try do
      Locations.find_suburbs_near_city(city, radius_km: 50, limit: 10)
    rescue
      e ->
        Logger.error("Error fetching suburbs for city: #{inspect(e)}")
        []
    end
  end

  # Filter venues based on selected suburbs
  defp filter_venues_by_suburbs(city, radius, selected_suburb_ids, suburbs) do
    # Extract suburb city objects from the suburbs list
    selected_suburbs = suburbs
      |> Enum.filter(fn %{city: suburb} -> suburb.id in selected_suburb_ids end)
      |> Enum.map(fn %{city: suburb} -> suburb end)

    if Enum.empty?(selected_suburbs) do
      # If no suburbs selected, just return all venues in radius
      get_venues_near_city(city, radius)
    else
      try do
        # For each selected suburb, get venues within 10km of it
        suburb_venues = Enum.flat_map(selected_suburbs, fn suburb ->
          Locations.find_venues_near_city(suburb, radius_km: 10, load_relations: true)
        end)

        # Filter out venues without events
        suburb_venues_with_events = Enum.filter(suburb_venues, fn %{venue: venue} ->
          venue.events && Enum.any?(venue.events)
        end)

        # Deduplicate venues and format them the same way as in get_venues_near_city
        suburb_venues_with_events
        |> Enum.uniq_by(fn %{venue: venue} -> venue.id end)
        |> Enum.map(fn %{venue: venue, distance_km: distance} ->
          try do
            # Extract event source data if available
            event_source_data = get_event_source_data(venue)

            # Ensure we have country data for currency detection
            venue_with_country = ensure_country_data(venue, city)

            %{
              venue: %{
                id: venue.id,
                name: venue.name,
                slug: venue.slug,
                address: venue.address,
                description: get_venue_description(venue),
                hero_image_url: get_venue_image(venue),
                rating: get_venue_rating(venue),
                events: Map.get(venue, :events, []),
                last_seen_at: event_source_data[:last_seen_at],
                source_name: event_source_data[:source_name],
                source_url: event_source_data[:source_url],
                # Add country_code to venue for currency detection
                country_code: get_country(venue_with_country).code
              },
              distance_km: distance
            }
          rescue
            e ->
              Logger.error("Error processing suburb venue data: #{inspect(e)}")
              # Return a simplified venue object with just the essential data
              %{
                venue: %{
                  id: venue.id,
                  name: venue.name,
                  slug: venue.slug,
                  address: venue.address || "No address available",
                  description: "Information for this venue is temporarily unavailable.",
                  hero_image_url: "/images/default-venue.jpg",
                  rating: 4.0,
                  events: [],
                  last_seen_at: nil,
                  source_name: nil,
                  source_url: nil,
                  # Add country_code from the parent city for proper currency formatting
                  country_code: city.country.code
                },
                distance_km: distance
              }
          end
        end)
      rescue
        e ->
          Logger.error("Error filtering venues by suburbs: #{inspect(e)}")
          # Fall back to default venues
          get_venues_near_city(city, radius)
      end
    end
  end

  # Ensure venue has country data by using city's country if necessary
  defp ensure_country_data(venue, city) do
    # If venue already has complete country data, return as is
    if venue.city && !is_struct(venue.city.country, Ecto.Association.NotLoaded) do
      venue
    else
      # Try to use city's country data
      try do
        # Use the put_in function to update the venue.city with the provided city
        # This will make city.country available for country code detection
        put_in(venue.city, city)
      rescue
        # If any error occurs (like path doesn't exist), return original venue
        _ -> venue
      end
    end
  end
end

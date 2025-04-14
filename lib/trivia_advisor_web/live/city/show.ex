defmodule TriviaAdvisorWeb.CityLive.Show do
  use TriviaAdvisorWeb, :live_view

  alias TriviaAdvisorWeb.CityLive.Components.Header
  alias TriviaAdvisorWeb.CityLive.Components.FilterBar
  alias TriviaAdvisorWeb.CityLive.Components.VenueList
  alias TriviaAdvisorWeb.CityLive.Helpers.CityShowHelpers

  require Logger

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
    case CityShowHelpers.get_city_data(slug) do
      {:ok, city_data} ->
        socket = socket
          |> assign(:page_title, "#{city_data.name} - Trivia Venues")
          |> assign(:city, city_data)
          |> assign(:radius, @default_radius)
          |> assign(:radius_options, @radius_options)
          |> assign(:selected_suburbs, [])
          |> assign(:suburbs, CityShowHelpers.get_suburbs(city_data.city))

        # Get venues for the city using spatial search
        {:ok, assign(socket, :venues, CityShowHelpers.get_venues_near_city(city_data.city, @default_radius))}

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
    venues = CityShowHelpers.get_venues_near_city(socket.assigns.city.city, radius)

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
      venues = CityShowHelpers.filter_venues_by_suburbs(
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
      CityShowHelpers.get_venues_near_city(socket.assigns.city.city, socket.assigns.radius)
    else
      CityShowHelpers.filter_venues_by_suburbs(
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
    venues = CityShowHelpers.get_venues_near_city(socket.assigns.city.city, socket.assigns.radius)

    {:noreply, socket
      |> assign(:selected_suburbs, [])
      |> assign(:venues, venues)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- City Hero Section -->
      <.live_component
        module={Header}
        id="city-header"
        city={@city}
      />

      <!-- Main Content -->
      <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <!-- Filters -->
        <.live_component
          module={FilterBar}
          id="city-filters"
          city={@city}
          radius={@radius}
          radius_options={@radius_options}
          selected_suburbs={@selected_suburbs}
          suburbs={@suburbs}
        />

        <!-- Venue List -->
        <.live_component
          module={VenueList}
          id="city-venues"
          venues={@venues}
          city={@city}
        />
      </div>
    </div>
    """
  end
end

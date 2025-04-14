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
        # Get suburbs and days of week for filters
        suburbs = CityShowHelpers.get_suburbs(city_data.city)
        days_of_week = CityShowHelpers.get_days_of_week(city_data.city, @default_radius)

        socket = socket
          |> assign(:page_title, "#{city_data.name} - Trivia Venues")
          |> assign(:city, city_data)
          |> assign(:radius, @default_radius)
          |> assign(:radius_options, @radius_options)
          |> assign(:selected_suburbs, [])
          |> assign(:suburbs, suburbs)
          |> assign(:selected_days, [])
          |> assign(:days_of_week, days_of_week)

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
         |> assign(:suburbs, [])
         |> assign(:selected_days, [])
         |> assign(:days_of_week, [])}
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

    # Update venues with new radius and recalculate days of week
    venues = CityShowHelpers.get_venues_near_city(socket.assigns.city.city, radius)
    days_of_week = CityShowHelpers.get_days_of_week(socket.assigns.city.city, radius)

    # Reset filters when radius changes
    {:noreply, socket
      |> assign(:radius, radius)
      |> assign(:venues, venues)
      |> assign(:selected_suburbs, [])
      |> assign(:selected_days, [])
      |> assign(:days_of_week, days_of_week)}
  end

  @impl true
  def handle_event("select-suburb", %{"suburb-id" => suburb_id}, socket) do
    suburb_id = String.to_integer(suburb_id)

    # Find the selected suburb data from the suburbs list
    suburb = Enum.find(socket.assigns.suburbs, fn %{city: city} -> city.id == suburb_id end)

    # Only proceed if the suburb exists and is not already selected
    if suburb && suburb_id not in socket.assigns.selected_suburbs do
      selected_suburbs = [suburb_id | socket.assigns.selected_suburbs]

      # Filter venues based on selected suburbs and days
      venues = CityShowHelpers.filter_venues_by_suburbs_and_days(
        socket.assigns.city.city,
        socket.assigns.radius,
        selected_suburbs,
        socket.assigns.suburbs,
        socket.assigns.selected_days
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

    # Filter venues based on remaining selected suburbs and days
    venues = CityShowHelpers.filter_venues_by_suburbs_and_days(
      socket.assigns.city.city,
      socket.assigns.radius,
      selected_suburbs,
      socket.assigns.suburbs,
      socket.assigns.selected_days
    )

    {:noreply, socket
      |> assign(:selected_suburbs, selected_suburbs)
      |> assign(:venues, venues)}
  end

  @impl true
  def handle_event("clear-suburbs", _params, socket) do
    # Clear suburb filters and update venues based on remaining day filters
    venues = if Enum.empty?(socket.assigns.selected_days) do
      CityShowHelpers.get_venues_near_city(socket.assigns.city.city, socket.assigns.radius)
    else
      CityShowHelpers.filter_venues_by_days(
        socket.assigns.city.city,
        socket.assigns.radius,
        socket.assigns.selected_days
      )
    end

    {:noreply, socket
      |> assign(:selected_suburbs, [])
      |> assign(:venues, venues)}
  end

  @impl true
  def handle_event("select-day", %{"day" => day}, socket) do
    day = String.to_integer(day)

    # Only proceed if the day exists and is not already selected
    if day in Enum.map(socket.assigns.days_of_week, & &1.day_of_week) && day not in socket.assigns.selected_days do
      selected_days = [day | socket.assigns.selected_days]

      # Filter venues based on selected days and suburbs
      venues = CityShowHelpers.filter_venues_by_suburbs_and_days(
        socket.assigns.city.city,
        socket.assigns.radius,
        socket.assigns.selected_suburbs,
        socket.assigns.suburbs,
        selected_days
      )

      {:noreply, socket
        |> assign(:selected_days, selected_days)
        |> assign(:venues, venues)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove-day", %{"day" => day}, socket) do
    day = String.to_integer(day)

    # Remove the day from the selected list
    selected_days = Enum.reject(socket.assigns.selected_days, fn d -> d == day end)

    # Filter venues based on remaining selected days and suburbs
    venues = CityShowHelpers.filter_venues_by_suburbs_and_days(
      socket.assigns.city.city,
      socket.assigns.radius,
      socket.assigns.selected_suburbs,
      socket.assigns.suburbs,
      selected_days
    )

    {:noreply, socket
      |> assign(:selected_days, selected_days)
      |> assign(:venues, venues)}
  end

  @impl true
  def handle_event("clear-days", _params, socket) do
    # Clear day filters and update venues based on remaining suburb filters
    venues = if Enum.empty?(socket.assigns.selected_suburbs) do
      CityShowHelpers.get_venues_near_city(socket.assigns.city.city, socket.assigns.radius)
    else
      CityShowHelpers.filter_venues_by_suburbs(
        socket.assigns.city.city,
        socket.assigns.radius,
        socket.assigns.selected_suburbs,
        socket.assigns.suburbs
      )
    end

    {:noreply, socket
      |> assign(:selected_days, [])
      |> assign(:venues, venues)}
  end

  @impl true
  def handle_event("clear-all-filters", _params, socket) do
    # Clear all filters and show all venues within radius
    venues = CityShowHelpers.get_venues_near_city(socket.assigns.city.city, socket.assigns.radius)

    {:noreply, socket
      |> assign(:selected_suburbs, [])
      |> assign(:selected_days, [])
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
          selected_days={@selected_days}
          days_of_week={@days_of_week}
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

defmodule TriviaAdvisorWeb.Live.Venue.Show do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisorWeb.VenueLive.Components.ImageGallery
  alias TriviaAdvisorWeb.JsonLd.EventSchema
  alias TriviaAdvisorWeb.JsonLd.BreadcrumbSchema
  alias TriviaAdvisorWeb.Live.Venue.Helpers.VenueShowHelpers
  alias TriviaAdvisorWeb.Live.Venue.Components.Header
  alias TriviaAdvisorWeb.Live.Venue.Components.MainContent
  alias TriviaAdvisorWeb.Live.Venue.Components.Sidebar
  require Logger

  import ImageGallery
  # Import all helper functions from the VenueShowHelpers module
  import VenueShowHelpers

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case get_venue_by_slug(slug) do
      {:redirect, venue} ->
        # This venue was merged, redirect to the primary venue
        {:ok,
          socket
          |> redirect(to: "/venues/#{venue.slug}")}

      {:ok, venue} ->
        # Add hero_image_url to venue
        venue = Map.put(venue, :hero_image_url, get_venue_image(venue))

        # Get nearby venues
        nearby_venues = get_nearby_venues(venue, 5)

        # Get country and city data for breadcrumbs
        country = get_country(venue)
        city = get_city(venue)

        # Get city name for title
        city_name = if is_map(city) && Map.has_key?(city, :name) && is_binary(city.name), do: city.name, else: "Unknown City"

        # Get organizer name for title
        organizer_name = try do
          if venue.events && Enum.any?(venue.events) do
            event = List.first(venue.events)
            if event && event.event_sources && is_list(event.event_sources) && Enum.any?(event.event_sources) do
              source = List.first(event.event_sources)
              if is_map(source) && Map.has_key?(source, :name) && is_binary(source.name), do: source.name, else: nil
            else
              nil
            end
          else
            # Try to get from metadata as fallback
            if is_map(venue.metadata) do
              venue.metadata["source_name"] || venue.metadata["organizer_name"]
            else
              nil
            end
          end
        rescue
          _ -> nil
        end

        # Build page title with organizer if available
        page_title = if is_binary(organizer_name) do
          limit_title_length("#{venue.name} · in #{city_name} by #{organizer_name} · QuizAdvisor")
        else
          limit_title_length("#{venue.name} · in #{city_name} · QuizAdvisor")
        end

        # Get Mapbox access token from config
        mapbox_token = Application.get_env(:trivia_advisor, :mapbox)[:access_token] || ""

        # Generate event JSON-LD data for structured data
        event_json_ld = EventSchema.generate_venue_event_json_ld(venue)

        # Generate breadcrumbs JSON-LD data
        breadcrumb_items = BreadcrumbSchema.create_venue_breadcrumbs(venue)
        breadcrumb_json_ld = BreadcrumbSchema.generate_breadcrumb_json_ld(breadcrumb_items)

        # Combine both JSON-LD snippets into an array
        json_ld_data = "[#{event_json_ld},#{breadcrumb_json_ld}]"

        # Get venue description for meta tags
        venue_description = get_meta_description(venue)

        # Get the thumbnail URL instead of original for consistent dimensions
        thumbnail_url = get_social_sharing_image(venue)

        # Use consistent dimensions based on how thumbnails are generated in the application
        # These should match the dimensions used in your uploader's transform function
        thumbnail_width = 800
        thumbnail_height = 420

        # Create Open Graph data for social sharing
        open_graph = %{
          type: "event",
          title: "Pub Quiz at #{venue.name} in #{city_name} · QuizAdvisor",
          description: venue_description,
          image_url: thumbnail_url,
          image_width: thumbnail_width,
          image_height: thumbnail_height,
          url: "#{TriviaAdvisorWeb.Endpoint.url()}/venues/#{venue.slug}"
        }

        {:ok,
          socket
          |> assign(:page_title, page_title)
          |> assign(:venue, venue)
          |> assign(:nearby_venues, nearby_venues)
          |> assign(:country, country)
          |> assign(:city, city)
          |> assign(:mapbox_token, mapbox_token)
          |> assign(:json_ld_data, json_ld_data)
          |> assign(:breadcrumb_items, breadcrumb_items)
          |> assign(:open_graph, open_graph)}

      {:error, _reason} ->
        # Default Open Graph data for not found page
        open_graph = %{
          type: "website",
          title: "Venue Not Found · QuizAdvisor",
          description: "We couldn't find the venue you're looking for. Discover other great pub quiz venues at QuizAdvisor.",
          image_url: "#{TriviaAdvisorWeb.Endpoint.url()}/images/default-venue-thumb.jpg",
          image_width: 800,
          image_height: 420,
          url: "#{TriviaAdvisorWeb.Endpoint.url()}/venues/#{slug}"
        }

        {:ok,
          socket
          |> assign(:page_title, "Venue Not Found · QuizAdvisor")
          |> assign(:venue, nil)
          |> assign(:nearby_venues, [])
          |> assign(:country, nil)
          |> assign(:city, nil)
          |> assign(:mapbox_token, "")
          |> assign(:breadcrumb_items, [%{name: "Home", url: "/"}, %{name: "Venue Not Found", url: nil}])
          |> assign(:open_graph, open_graph)
          |> put_flash(:error, "Venue not found")}
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
    assigns = assign(assigns, :get_venue_image_at_position, &get_venue_image_at_position/2)
    assigns = assign(assigns, :count_available_images, &count_available_images/1)

    ~H"""
    <div>
      <div class="mx-auto max-w-7xl px-4 py-8">
        <.live_component module={Header} id="venue-header" venue={@venue} breadcrumb_items={@breadcrumb_items} />

        <!-- Photo Gallery -->
        <%= if @venue do %>
          <.gallery
            venue={@venue}
            get_venue_image_at_position={@get_venue_image_at_position}
            count_available_images={@count_available_images}
          />
        <% else %>
          <div class="mb-8 overflow-hidden rounded-lg">
            <div class="w-full p-1">
              <img
                src={"https://placehold.co/1200x400?text=Venue Not Found"}
                alt="Venue Not Found"
                class="h-96 w-full object-cover rounded-lg"
              />
            </div>
          </div>
        <% end %>

        <div class="grid gap-8 md:grid-cols-3">
          <!-- Main Content -->
          <div class="md:col-span-2">
            <.live_component
              module={MainContent}
              id="venue-main-content"
              venue={@venue}
              nearby_venues={@nearby_venues}
              country={@country}
            />
          </div>

          <!-- Sidebar -->
          <div>
            <.live_component
              module={Sidebar}
              id="venue-sidebar"
              venue={@venue}
              country={@country}
              mapbox_token={@mapbox_token}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end

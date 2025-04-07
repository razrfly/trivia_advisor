defmodule TriviaAdvisorWeb.Live.Venue.Show do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisor.Locations
  alias TriviaAdvisorWeb.VenueLive.Components.ImageGallery
  alias TriviaAdvisorWeb.Helpers.FormatHelpers
  alias TriviaAdvisorWeb.Helpers.LocalizationHelpers
  alias TriviaAdvisorWeb.JsonLd.EventSchema
  alias TriviaAdvisorWeb.JsonLd.BreadcrumbSchema
  require Logger

  import ImageGallery
  import FormatHelpers, only: [
    has_event_source?: 1,
    format_last_updated: 1,
    format_active_since: 1,
    get_source_name: 1,
    format_day_of_week: 1
  ]
  import LocalizationHelpers, only: [format_localized_time: 2]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case get_venue_by_slug(slug) do
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
        <!-- Breadcrumbs -->
        <TriviaAdvisorWeb.Components.Breadcrumbs.breadcrumbs items={@breadcrumb_items} class="mb-4" />

        <!-- Venue Title -->
        <h1 class="mb-6 text-3xl font-bold text-gray-900"><%= @venue.name %></h1>

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
            <!-- Key Details -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <div class="mb-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
                <div class="flex flex-col">
                  <h3 class="mb-2 flex items-center text-sm font-medium text-gray-500">
                    <svg class="mr-1.5 h-5 w-5 text-indigo-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M5.75 2a.75.75 0 01.75.75V4h7V2.75a.75.75 0 011.5 0V4h.25A2.75 2.75 0 0118 6.75v8.5A2.75 2.75 0 0115.25 18H4.75A2.75 2.75 0 012 15.25v-8.5A2.75 2.75 0 014.75 4H5V2.75A.75.75 0 015.75 2zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75z" clip-rule="evenodd" />
                    </svg>
                    Quiz Day
                  </h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= format_day(get_day_of_week(@venue)) %></p>
                </div>
                <div class="flex flex-col">
                  <h3 class="mb-2 flex items-center text-sm font-medium text-gray-500">
                    <svg class="mr-1.5 h-5 w-5 text-indigo-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z" clip-rule="evenodd" />
                    </svg>
                    Start Time
                  </h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= format_localized_time(get_start_time(@venue), @country) %></p>
                </div>
                <div class="flex flex-col">
                  <h3 class="mb-2 flex items-center text-sm font-medium text-gray-500">
                    <svg class="mr-1.5 h-5 w-5 text-indigo-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M10.75 10.818v2.614A3.13 3.13 0 0011.888 13c.482-.315.612-.648.612-.875 0-.227-.13-.56-.612-.875a3.13 3.13 0 00-1.138-.432zM8.33 8.62c.053.055.115.11.184.164.208.208.46.284.736.363V6.603a2.45 2.45 0 00-.35.13c-.14.065-.27.143-.386.233-.377.292-.514.627-.514.909 0 .184.058.39.202.592.037.051.08.102.128.152z" />
                      <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-6a.75.75 0 01.75.75v.316a3.78 3.78 0 011.653.713c.426.33.744.74.925 1.2a.75.75 0 01-1.395.55 1.35 1.35 0 00-.447-.563 2.187 2.187 0 00-.736-.363V9.3c.698.093 1.383.32 1.959.696.787.514 1.29 1.27 1.29 2.13 0 .86-.504 1.616-1.29 2.13-.576.377-1.261.603-1.96.696v.299a.75.75 0 11-1.5 0v-.3c-.697-.092-1.382-.318-1.958-.695-.482-.315-.857-.717-1.078-1.188a.75.75 0 111.359-.636c.08.173.245.376.54.569.313.205.706.353 1.138.432v-2.748a3.782 3.782 0 01-1.653-.713C6.9 9.433 6.5 8.681 6.5 7.875c0-.805.4-1.558 1.097-2.096a3.78 3.78 0 011.653-.713V4.75A.75.75 0 0110 4z" clip-rule="evenodd" />
                    </svg>
                    Entry Fee
                  </h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900">
                    <%= if get_entry_fee_cents(@venue) do %>
                      <%= format_currency(get_entry_fee_cents(@venue), get_country_currency(@venue)) %>
                    <% else %>
                      Free
                    <% end %>
                  </p>
                </div>
                <div class="flex flex-col">
                  <h3 class="mb-2 flex items-center text-sm font-medium text-gray-500">
                    <svg class="mr-1.5 h-5 w-5 text-indigo-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M5.75 2a.75.75 0 01.75.75V4h7V2.75a.75.75 0 011.5 0V4h.25A2.75 2.75 0 0118 6.75v8.5A2.75 2.75 0 0115.25 18H4.75A2.75 2.75 0 012 15.25v-8.5A2.75 2.75 0 014.75 4H5V2.75A.75.75 0 015.75 2zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75z" clip-rule="evenodd" />
                    </svg>
                    Frequency
                  </h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900 capitalize"><%= get_frequency(@venue) %></p>
                </div>
              </div>
            </div>

            <!-- Description -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <h2 class="mb-4 text-xl font-bold text-gray-900">About This Trivia Night</h2>
              <div class="prose prose-indigo max-w-none">
                <p><%= get_venue_description(@venue) %></p>
              </div>

              <!-- Event Source Info -->
              <%= if has_event_source?(@venue) do %>
                <div class="mt-4 flex items-center space-x-1 text-sm text-gray-500">
                  <span>Updated <%= format_last_updated(@venue) %></span>
                  <span>•</span>
                  <span>Active since <%= format_active_since(@venue) %></span>
                  <span>•</span>
                  <span>Source:
                    <% source = get_source_name(@venue) %>
                    <%= if source.url do %>
                      <a href={source.url} target="_blank" class="text-indigo-600 hover:text-indigo-800"><%= source.name %></a>
                    <% else %>
                      <%= source.name %>
                    <% end %>
                  </span>
                </div>
              <% end %>
            </div>

            <!-- Nearby Venues -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <div class="mb-4 flex items-center justify-between">
                <h2 class="text-xl font-bold text-gray-900">Nearby Trivia Venues</h2>
              </div>

              <%= if length(@nearby_venues) > 0 do %>
                <div class="space-y-4">
                  <%= for venue_info <- @nearby_venues do %>
                    <div class="flex items-center space-x-4 rounded-lg border p-4 transition hover:bg-gray-50">
                      <div class="h-16 w-16 flex-shrink-0 overflow-hidden rounded-md">
                        <img
                          src={venue_info.venue.hero_image_url || get_venue_image(venue_info.venue) || "https://placehold.co/100x100?text=#{venue_info.venue.name}"}
                          alt={venue_info.venue.name}
                          class="h-full w-full object-cover"
                        />
                      </div>
                      <div class="flex-1 min-w-0">
                        <a href={~p"/venues/#{venue_info.venue.slug}"} class="block text-lg font-medium text-gray-900 hover:text-indigo-600">
                          <%= venue_info.venue.name %>
                        </a>
                        <p class="text-sm text-gray-500"><%= venue_info.venue.address %></p>
                        <p class="text-sm text-gray-500">
                          <span class="font-medium text-indigo-600"><%= format_distance(venue_info.distance_km) %></span> away
                        </p>
                      </div>
                      <div>
                        <span class="inline-flex rounded-full bg-indigo-100 px-2 py-1 text-xs font-semibold text-indigo-800">
                          <%= format_day(get_day_of_week(venue_info.venue)) %>s
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="py-8 text-center text-gray-500">
                  <p>No nearby venues found.</p>
                </div>
              <% end %>
            </div>

            <!-- Reviews -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <div class="mb-4 flex items-center justify-between">
                <h2 class="text-xl font-bold text-gray-900">Reviews</h2>
                <button class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                  Write a Review
                </button>
              </div>

              <%= if length(get_venue_reviews(@venue)) > 0 do %>
                <div class="divide-y divide-gray-200">
                  <%= for review <- get_venue_reviews(@venue) do %>
                    <div class="py-4">
                      <div class="mb-2 flex items-center">
                        <div class="flex">
                          <%= for i <- 1..5 do %>
                            <svg
                              class={"h-4 w-4 #{if i <= review.rating, do: "text-yellow-400", else: "text-gray-300"}"}
                              xmlns="http://www.w3.org/2000/svg"
                              viewBox="0 0 20 20"
                              fill="currentColor"
                            >
                              <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                            </svg>
                          <% end %>
                        </div>
                        <span class="ml-2 text-sm font-medium text-gray-900"><%= review.user_name %></span>
                        <span class="mx-2 text-sm text-gray-500">•</span>
                        <span class="text-sm text-gray-500"><%= review.date %></span>
                      </div>
                      <p class="text-gray-600"><%= review.comment %></p>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="py-8 text-center text-gray-500">
                  <p>No reviews yet. Be the first to review this venue!</p>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Sidebar -->
          <div>
            <!-- Map -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <h3 class="mb-4 text-lg font-semibold text-gray-900">Location</h3>
              <div class="h-64 overflow-hidden rounded-md">
                <%= if @venue && @venue.latitude && @venue.longitude do %>
                  <img
                    src={get_static_map_url(@venue, @mapbox_token)}
                    alt="Map of #{@venue.name}"
                    class="h-full w-full object-cover"
                  />
                <% else %>
                  <div class="flex h-full w-full items-center justify-center bg-gray-200">
                    <p class="text-gray-500">Map not available</p>
                  </div>
                <% end %>
              </div>
              <div class="mt-4">
                <p class="text-gray-600"><%= @venue.address %></p>
                <a
                  href={get_directions_url(@venue)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="mt-2 inline-flex items-center text-sm font-medium text-indigo-600 hover:text-indigo-700"
                >
                  Get directions
                  <svg class="ml-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M3 10a.75.75 0 01.75-.75h10.638L10.23 5.29a.75.75 0 111.04-1.08l5.5 5.25a.75.75 0 010 1.08l-5.5 5.25a.75.75 0 11-1.04-1.08l4.158-3.96H3.75A.75.75 0 013 10z" clip-rule="evenodd" />
                  </svg>
                </a>
              </div>
            </div>

            <!-- Contact Info -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <h3 class="mb-4 text-lg font-semibold text-gray-900">Contact</h3>
              <div class="space-y-3">
                <%= if @venue.phone do %>
                  <div class="flex items-start">
                    <svg class="mr-3 h-5 w-5 flex-shrink-0 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M2 3.5A1.5 1.5 0 013.5 2h1.148a1.5 1.5 0 011.465 1.175l.716 3.223a1.5 1.5 0 01-1.052 1.767l-.933.267c-.41.117-.643.555-.48.95a11.542 11.542 0 006.254 6.254c.395.163.833-.07.95-.48l.267-.933a1.5 1.5 0 011.767-1.052l3.223.716A1.5 1.5 0 0118 15.352V16.5a1.5 1.5 0 01-1.5 1.5H15c-1.149 0-2.263-.15-3.326-.43A13.022 13.022 0 012.43 8.326 13.019 13.019 0 012 5V3.5z" clip-rule="evenodd" />
                    </svg>
                    <a href={"tel:#{@venue.phone}"} class="text-gray-600 hover:text-indigo-600"><%= @venue.phone %></a>
                  </div>
                <% end %>

                <%= if @venue.website do %>
                  <div class="flex items-start">
                    <svg class="mr-3 h-5 w-5 flex-shrink-0 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M5.22 14.78a.75.75 0 001.06 0l7.22-7.22v5.69a.75.75 0 001.5 0v-7.5a.75.75 0 00-.75-.75h-7.5a.75.75 0 000 1.5h5.69l-7.22 7.22a.75.75 0 000 1.06z" clip-rule="evenodd" />
                    </svg>
                    <a href={@venue.website} target="_blank" rel="noopener noreferrer" class="text-gray-600 hover:text-indigo-600">Visit website</a>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Next Event -->
            <div class="overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <h3 class="mb-4 text-lg font-semibold text-gray-900">Next Quiz Night</h3>
              <div class="rounded-md bg-indigo-50 p-4">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-indigo-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z" clip-rule="evenodd" />
                    </svg>
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-indigo-800">
                      <%= format_day(get_day_of_week(@venue)) %>, <%= format_next_date(get_day_of_week(@venue)) %>
                    </h3>
                    <div class="mt-2 text-sm text-indigo-700">
                      <p>Starts at <%= format_localized_time(get_start_time(@venue), @country) %></p>
                    </div>
                    <div class="mt-4">
                      <div class="-mx-2 -my-1.5 flex">
                        <button class="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700">
                          Add to Calendar
                        </button>
                        <button class="ml-3 rounded-md bg-indigo-100 px-3 py-1.5 text-sm font-medium text-indigo-800 hover:bg-indigo-200">
                          Set Reminder
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Quiz Master -->
            <%= if event = get_event_with_performer(@venue) do %>
              <div class="mt-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
                <h3 class="mb-4 text-lg font-semibold text-gray-900">Quiz Master</h3>
                <div class="flex items-center">
                  <%= if event.performer.profile_image do %>
                    <div class="h-12 w-12 flex-shrink-0 overflow-hidden rounded-full">
                      <img
                        src={
                          try do
                            cond do
                              is_map(event.performer.profile_image) ->
                                # Call the standard URL function which handles nil safely, then ensure it's a full URL
                                raw_url = TriviaAdvisor.Uploaders.ProfileImage.url({event.performer.profile_image, event.performer}, :original)
                                ensure_full_url(raw_url)
                              is_binary(event.performer.profile_image) ->
                                event.performer.profile_image
                              true ->
                                TriviaAdvisor.Uploaders.ProfileImage.default_url(nil, nil)
                            end
                          rescue
                            e ->
                              Logger.error("Error getting profile image: #{Exception.message(e)}")
                              TriviaAdvisor.Uploaders.ProfileImage.default_url(nil, nil)
                          end
                        }
                        alt={event.performer.name}
                        class="h-full w-full object-cover"
                      />
                    </div>
                  <% else %>
                    <div class="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-indigo-100">
                      <svg class="h-6 w-6 text-indigo-600" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
                        <path fill-rule="evenodd" d="M7.5 6a4.5 4.5 0 119 0 4.5 4.5 0 01-9 0zM3.751 20.105a8.25 8.25 0 0116.498 0 .75.75 0 01-.437.695A18.683 18.683 0 0112 22.5c-2.786 0-5.433-.608-7.812-1.7a.75.75 0 01-.437-.695z" clip-rule="evenodd" />
                      </svg>
                    </div>
                  <% end %>
                  <div class="ml-4">
                    <h4 class="text-base font-medium text-gray-900"><%= event.performer.name %></h4>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_venue_by_slug(slug) do
    try do
      # Try to get venue from database using slug
      venue = Locations.get_venue_by_slug(slug)
      |> Locations.load_venue_relations()
      |> TriviaAdvisor.Repo.preload(city: :country)

      if venue do
        {:ok, venue}
      else
        {:error, :not_found}
      end
    rescue
      e ->
        Logger.error("Failed to get venue: #{inspect(e)}")
        {:error, :not_found}
    end
  end

  # Helper to get day of week from venue events
  defp get_day_of_week(venue) do
    # Get the day of week from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :day_of_week)
    else
      # Default value if no events
      1 # Monday as default
    end
  end

  # Helper to get start time from venue events
  defp get_start_time(venue) do
    # Get the start time from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :start_time)
    else
      # Default value if no events
      "7:00 PM"
    end
  end

  defp format_next_date(day_of_week) when is_integer(day_of_week) do
    today = Date.utc_today()
    today_day = Date.day_of_week(today)

    # Calculate days until the next occurrence
    days_until = if day_of_week >= today_day do
      day_of_week - today_day
    else
      7 - today_day + day_of_week
    end

    # Get the date of the next occurrence
    next_date = Date.add(today, days_until)

    # Format as "Month Day" (e.g., "May 15")
    month = case next_date.month do
      1 -> "Jan"
      2 -> "Feb"
      3 -> "Mar"
      4 -> "Apr"
      5 -> "May"
      6 -> "Jun"
      7 -> "Jul"
      8 -> "Aug"
      9 -> "Sep"
      10 -> "Oct"
      11 -> "Nov"
      12 -> "Dec"
    end

    "#{month} #{next_date.day}"
  end

  defp format_next_date(_), do: "TBA"

  # Helper to get reviews from venue or return empty list if they don't exist
  defp get_venue_reviews(venue) do
    # Return empty list if venue has no reviews field
    Map.get(venue, :reviews, [])
  end

  # Get venue image - updated to use the new ImageUrlHelper
  defp get_venue_image(venue) do
    alias TriviaAdvisor.Helpers.ImageUrlHelper

    try do
      # Check for events with hero_image
      {_event, event_image_url} =
        try do
          if venue.events && Enum.any?(venue.events) do
            event = List.first(venue.events)

            image_url = if event && event.hero_image && event.hero_image.file_name do
              try do
                # Use helper to generate URL
                ImageUrlHelper.get_image_url({event.hero_image.file_name, event}, TriviaAdvisor.Uploaders.HeroImage, :original)
              rescue
                e ->
                  Logger.error("Error processing hero image URL: #{Exception.message(e)}")
                  nil
              end
            else
              nil
            end

            {event, image_url}
          else
            {nil, nil}
          end
        rescue
          _ -> {nil, nil}
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
      image_url = event_image_url || google_place_image || metadata_image || venue_image

      if is_binary(image_url) do
        # Use helper to ensure it's a full URL
        ImageUrlHelper.ensure_full_url(image_url)
      else
        # If no valid image URL is found, return a default image URL
        "#{TriviaAdvisorWeb.Endpoint.url()}/images/default-venue-thumb.jpg"
      end
    rescue
      e ->
        Logger.error("Error getting venue image: #{inspect(e)}")
        "#{TriviaAdvisorWeb.Endpoint.url()}/images/default-venue-thumb.jpg"
    end
  end

  # Helper to get entry fee cents from venue events
  defp get_entry_fee_cents(venue) do
    # Get the entry fee from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :entry_fee_cents)
    else
      nil # Free by default
    end
  end

  # Helper to get frequency from venue events
  defp get_frequency(venue) do
    # Get the frequency from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :frequency, "Weekly") # Default to weekly if not found
    else
      "Weekly" # Default value if no events
    end
  end

  # Helper to get description from venue events
  defp get_venue_description(venue) do
    # Get the description from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :description, "No description available.") # Default message if not found
    else
      # If no events, check if description is in metadata
      venue.metadata["description"] || "No description available for this trivia night."
    end
  end

  # Get nearby venues
  defp get_nearby_venues(venue, limit) do
    if venue.latitude && venue.longitude do
      # Convert Decimal values to floats
      lat = to_float(venue.latitude)
      lng = to_float(venue.longitude)

      coords = {lat, lng}

      # Find nearby venues
      nearby_venues = TriviaAdvisor.Locations.find_venues_near_coordinates(coords,
        radius_km: 25,
        limit: limit + 1, # Get one extra to filter out the current venue
        load_relations: true
      )

      # Filter out the current venue and limit to specified number
      nearby_venues
      |> Enum.reject(fn %{venue: nearby} -> nearby.id == venue.id end)
      |> Enum.take(limit)
      |> Enum.map(fn %{venue: nearby, distance_km: distance} ->
        # Add hero_image_url to each venue
        updated_venue = Map.put(nearby, :hero_image_url, get_venue_image(nearby))
        %{venue: updated_venue, distance_km: distance}
      end)
    else
      []
    end
  end

  # Helper to convert Decimal to float
  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value), do: value

  # Count real available images (no fallbacks)
  defp count_available_images(venue) do
    # Count Google images
    google_images_count = if venue.google_place_images && is_list(venue.google_place_images),
      do: length(venue.google_place_images),
      else: 0

    # Count event hero image
    event_image_count = if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      if event.hero_image && event.hero_image.file_name, do: 1, else: 0
    else
      0
    end

    # Return total
    google_images_count + event_image_count
  end

  # Modified version to properly combine all image sources with consistent ordering
  defp get_venue_image_at_position(venue, position) do
    alias TriviaAdvisor.Helpers.ImageUrlHelper

    # Check for events with hero_image
    {_event, event_image_url} =
      try do
        if venue.events && Enum.any?(venue.events) do
          event = List.first(venue.events)

          image_url = if event && event.hero_image && event.hero_image.file_name do
            try do
              # Use helper to generate URL
              ImageUrlHelper.get_image_url({event.hero_image.file_name, event}, TriviaAdvisor.Uploaders.HeroImage, :original)
            rescue
              e ->
                Logger.error("Error processing hero image URL: #{Exception.message(e)}")
                nil
            end
          else
            nil
          end

          {event, image_url}
        else
          {nil, nil}
        end
      rescue
        _ -> {nil, nil}
      end

    # Get Google images if available (ensuring they're valid)
    google_images =
      try do
        if venue.google_place_images && is_list(venue.google_place_images) do
          venue.google_place_images
          |> Enum.filter(fn img -> is_map(img) end)
          |> Enum.sort_by(fn img -> Map.get(img, "position", 999) end)  # Sort by position
        else
          []
        end
      rescue
        _ -> []
      end

    # Combine all available images with hero image first
    all_images = []

    # Add hero image first if available
    all_images = if is_binary(event_image_url), do: [event_image_url | all_images], else: all_images

    # Add all Google images safely
    google_image_urls =
      try do
        api_key = get_google_api_key()

        if api_key && is_binary(api_key) do
          google_images
          |> Enum.map(fn image_data ->
            try do
              cond do
                # Handle Places API (New) format with photo_name
                is_map(image_data) &&
                is_map_key(image_data, "photo_name") &&
                is_binary(image_data["photo_name"]) ->
                  "https://places.googleapis.com/v1/#{image_data["photo_name"]}/media?key=#{api_key}&maxHeightPx=800"

                # Handle legacy Places API format with photo_reference
                is_map(image_data) &&
                is_map_key(image_data, "photo_reference") &&
                is_binary(image_data["photo_reference"]) ->
                  "https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=#{image_data["photo_reference"]}&key=#{api_key}"

                # Handle other legacy formats
                is_map(image_data) &&
                is_map_key(image_data, "local_path") &&
                is_binary(image_data["local_path"]) ->
                  ImageUrlHelper.ensure_full_url(image_data["local_path"])

                is_map(image_data) &&
                is_map_key(image_data, "original_url") &&
                is_binary(image_data["original_url"]) ->
                  image_data["original_url"]

                true ->
                  nil
              end
            rescue
              _ -> nil
            end
          end)
          |> Enum.filter(fn url -> is_binary(url) end)
        else
          []
        end
      rescue
        _ -> []
      end

    all_images = all_images ++ google_image_urls

    # Now get the image at the requested position
    if position < length(all_images) && Enum.any?(all_images) do
      image = Enum.at(all_images, position)
      if is_binary(image), do: image, else: return_default_image(venue)
    else
      # If no image exists for this position, use a default image
      return_default_image(venue)
    end
  end

  defp return_default_image(venue \\ nil) do
    if venue && is_map(venue) && Map.has_key?(venue, :name) && is_binary(venue.name) do
      "https://placehold.co/600x400?text=#{URI.encode(venue.name)}"
    else
      "#{TriviaAdvisorWeb.Endpoint.url()}/images/default-venue-thumb.jpg"
    end
  end

  # Add function to get the Google API key
  defp get_google_api_key do
    # First try to get from environment variable directly
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 ->
        key
      _ ->
        # Fall back to application config
        Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI)[:google_maps_api_key]
    end
  end

  # Format distance for display
  defp format_distance(distance_km) when is_float(distance_km) do
    cond do
      distance_km < 1 -> "#{round(distance_km * 1000)} m"
      true -> "#{:erlang.float_to_binary(distance_km, [decimals: 1])} km"
    end
  end
  defp format_distance(_), do: "Unknown distance"

  # Helper to ensure URL is a full URL
  defp ensure_full_url(path) do
    # Return a default image if path is nil or not a binary
    if is_nil(path) or not is_binary(path) do
      return_default_image()
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

          # Local development - use the app's URL config
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
          return_default_image()
      end
    end
  end

  # Helper to get country information
  defp get_country(venue) do
    country = cond do
      # Check if venue has a direct country_code
      Map.has_key?(venue, :country_code) ->
        %{code: venue.country_code, name: "Unknown", slug: "unknown"}
      # Try to safely extract country from city if it exists
      true ->
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

    # Debug log for venues related to France
    if venue.slug == "bar-le-national" do
      Logger.debug("Country for bar-le-national: #{inspect(country)}")
    end

    country
  end

  # Helper to get city information
  defp get_city(venue) do
    if venue.city && !is_struct(venue.city, Ecto.Association.NotLoaded) do
      venue.city
    else
      # Fallback if city is not available or not loaded
      %{name: "Unknown", slug: "unknown"}
    end
  end

  # Helper to get country's currency
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

  # Helper to format currency with proper symbol and localization
  defp format_currency(amount_cents, currency_code) when is_number(amount_cents) do
    # Create Money struct with proper currency
    money = Money.new(amount_cents, currency_code)

    # Let the Money library handle the formatting
    Money.to_string(money)
  end
  defp format_currency(_, _), do: "Free"

  # Helper to generate a Mapbox static map URL
  defp get_static_map_url(venue, token) when is_binary(token) and byte_size(token) > 0 do
    # Convert Decimal to float if needed
    {lat, lng} = {to_float(venue.latitude), to_float(venue.longitude)}

    # Create a marker pin at the venue's coordinates
    marker = "pin-l-star+f74e4e(#{lng},#{lat})"
    # Size of the map image
    size = "600x400"
    # Zoom level (higher numbers = more zoomed in)
    zoom = 19
    # Use custom Mapbox style instead of default streets style
    style = "holden/cm7pbsjwv004401sc5z5ldatr"

    # Construct the URL
    "https://api.mapbox.com/styles/v1/#{style}/static/#{marker}/#{lng},#{lat},#{zoom}/#{size}?access_token=#{token}"
  end

  # Fallback if token is missing
  defp get_static_map_url(venue, _token) do
    "https://placehold.co/600x400?text=Map+for+#{URI.encode(venue.name)}"
  end

  # Create a directions URL to Google Maps
  defp get_directions_url(venue) do
    # Convert Decimal to float if needed
    lat = to_float(venue.latitude)
    lng = to_float(venue.longitude)

    # Use Google Maps directions URL with coordinates
    "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lng}&destination_place_id=#{venue.place_id}"
  end

  # Helper to format day name from day of week number
  defp format_day(day) when is_integer(day) do
    format_day_of_week(day)
  end

  defp format_day(_), do: "TBA"

  # Helper to check if performer is loaded
  defp performer_loaded?(event) do
    event &&
    event.performer &&
    !is_struct(event.performer, Ecto.Association.NotLoaded) &&
    event.performer.name
  end

  # Helper to get first event that has performer data
  defp get_event_with_performer(venue) do
    if venue.events && Enum.any?(venue.events) do
      Enum.find(venue.events, fn event -> performer_loaded?(event) end)
    else
      nil
    end
  end

  # Helper to limit title length to 60 characters for SEO (Google typically shows ~60 chars)
  defp limit_title_length(title) when is_binary(title) do
    max_length = 60

    if String.length(title) <= max_length do
      title
    else
      # Try to smartly truncate at a separator
      separators = [" · ", " by ", " in ", " ", "-"]

      # Try each separator, starting from the right side of the string
      Enum.reduce_while(separators, title, fn separator, acc ->
        # Find the rightmost position of the separator
        case String.split(acc, separator, parts: :infinity) do
          parts when length(parts) > 1 ->
            # Try removing parts from the end until we're under the max length
            Enum.reduce_while(1..length(parts), parts, fn i, parts_acc ->
              truncated = parts_acc |> Enum.drop(-i) |> Enum.join(separator)

              if String.length(truncated) <= max_length - 3 do
                # We found a good truncation point, add ellipsis and stop
                {:halt, {:halt, truncated <> "..."}}
              else
                # Keep trying with more parts removed
                {:cont, parts_acc}
              end
            end)
          _ ->
            # This separator isn't in the string or didn't help, try the next one
            {:cont, acc}
        end
      end)
      |> case do
        {:halt, result} -> result
        _ -> String.slice(title, 0, max_length - 3) <> "..."  # Hard truncate as fallback
      end
    end
  end

  # Helper to create a meta description for social sharing
  defp get_meta_description(venue) do
    # Get next quiz date
    next_date = format_next_date(get_day_of_week(venue))
    day = format_day(get_day_of_week(venue))
    start_time = get_start_time(venue)

    # Check if there's a venue description available
    venue_desc = get_venue_description(venue)

    # Get organizer name if available
    organizer =
      try do
        if venue.events && Enum.any?(venue.events) do
          event = List.first(venue.events)
          if event && event.event_sources && is_list(event.event_sources) && Enum.any?(event.event_sources) do
            source = List.first(event.event_sources)
            if is_map(source) && Map.has_key?(source, :name) && is_binary(source.name), do: source.name, else: nil
          end
        else
          if is_map(venue.metadata), do: venue.metadata["source_name"], else: nil
        end
      rescue
        _ -> nil
      end

    # Create description based on available data
    cond do
      # If we have a venue description, date, time and organizer
      is_binary(venue_desc) && byte_size(venue_desc) > 10 && is_binary(organizer) ->
        # Truncate description if too long
        short_desc = if String.length(venue_desc) > 80, do: String.slice(venue_desc, 0, 80) <> "...", else: venue_desc
        "#{short_desc} Join us on #{next_date} (#{day}) at #{start_time}. Hosted by #{organizer}."

      # If we have a venue description but no organizer
      is_binary(venue_desc) && byte_size(venue_desc) > 10 ->
        short_desc = if String.length(venue_desc) > 100, do: String.slice(venue_desc, 0, 100) <> "...", else: venue_desc
        "#{short_desc} Join us on #{next_date} (#{day}) at #{start_time}."

      # If we have just the basic details
      true ->
        if is_binary(organizer) do
          "Join our pub quiz at #{venue.name} on #{day}s at #{start_time}. Hosted by #{organizer}. Meet other trivia enthusiasts and test your knowledge!"
        else
          "Join our pub quiz at #{venue.name} on #{day}s at #{start_time}. Meet other trivia enthusiasts and test your knowledge!"
        end
    end
  end

  # Helper to get the thumbnail URL for social sharing
  defp get_social_sharing_image(venue) do
    alias TriviaAdvisor.Helpers.ImageUrlHelper

    # Get the venue image
    image_url = get_venue_image(venue)

    # Check if the image URL is valid
    if is_binary(image_url) and String.length(image_url) > 0 do
      # Convert from original to thumbnail URL
      # For paths containing /original_ in the URL, replace with /thumb_
      if String.contains?(image_url, "/original_") do
        String.replace(image_url, "/original_", "/thumb_")
      else
        # If it's not a standard path with original, just use the original image
        image_url
      end
    else
      # If no valid image URL is found, return a default image URL
      "#{TriviaAdvisorWeb.Endpoint.url()}/images/default-venue-thumb.jpg"
    end
  end
end

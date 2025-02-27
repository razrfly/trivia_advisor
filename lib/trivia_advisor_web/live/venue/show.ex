defmodule TriviaAdvisorWeb.VenueLive.Show do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisor.Services.UnsplashService
  alias TriviaAdvisor.Services.GooglePlacesService
  alias TriviaAdvisor.Locations
  require Logger

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Get venue from database by slug instead of id
    case get_venue_by_slug(slug) do
      {:ok, venue} ->
        # Add hero_image_url to venue
        venue = Map.put(venue, :hero_image_url, get_venue_image(venue))

        # Get nearby venues
        nearby_venues = get_nearby_venues(venue, 5)

        {:ok,
          socket
          |> assign(:page_title, "#{venue.name} - TriviaAdvisor")
          |> assign(:venue, venue)
          |> assign(:nearby_venues, nearby_venues)}

      {:error, _reason} ->
        {:ok,
          socket
          |> assign(:page_title, "Venue Not Found - TriviaAdvisor")
          |> assign(:venue, nil)
          |> assign(:nearby_venues, [])
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
    ~H"""
    <div>
      <div class="mx-auto max-w-7xl px-4 py-8">
        <!-- Venue Title -->
        <h1 class="mb-6 text-3xl font-bold text-gray-900"><%= @venue.name %></h1>

        <!-- Photo Gallery -->
        <div class="mb-8 overflow-hidden rounded-lg">
          <div class="flex flex-wrap">
            <%= if @venue && venue_has_images?(@venue) do %>
              <div class="w-1/2 p-1">
                <img
                  src={get_venue_image_at_position(@venue, 0)}
                  alt={@venue.name}
                  class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
                />
              </div>
              <div class="w-1/2">
                <div class="flex flex-wrap">
                  <div class="w-1/2 p-1">
                    <img
                      src={get_venue_image_at_position(@venue, 1)}
                      alt={@venue.name}
                      class="h-48 w-full object-cover rounded-tr-lg"
                    />
                  </div>
                  <div class="w-1/2 p-1">
                    <img
                      src={get_venue_image_at_position(@venue, 2)}
                      alt={@venue.name}
                      class="h-48 w-full object-cover"
                    />
                  </div>
                  <div class="w-1/2 p-1">
                    <img
                      src={get_venue_image_at_position(@venue, 3)}
                      alt={@venue.name}
                      class="h-48 w-full object-cover"
                    />
                  </div>
                  <div class="w-1/2 p-1">
                    <img
                      src={get_venue_image_at_position(@venue, 4)}
                      alt={@venue.name}
                      class="h-48 w-full object-cover rounded-br-lg"
                    />
                  </div>
                </div>
              </div>
            <% else %>
              <div class="w-full p-1">
                <img
                  src={@venue.hero_image_url || "https://placehold.co/1200x400?text=#{@venue.name}"}
                  alt={@venue.name}
                  class="h-96 w-full object-cover rounded-lg"
                />
              </div>
            <% end %>
          </div>
        </div>

        <div class="grid gap-8 md:grid-cols-3">
          <!-- Main Content -->
          <div class="md:col-span-2">
            <!-- Key Details -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <div class="mb-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Quiz Day</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= format_day(get_day_of_week(@venue)) %></p>
                </div>
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Start Time</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= get_start_time(@venue) %></p>
                </div>
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Entry Fee</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900">
                    <%= if get_entry_fee_cents(@venue) do %>
                      $<%= :erlang.float_to_binary(get_entry_fee_cents(@venue) / 100, [decimals: 2]) %>
                    <% else %>
                      Free
                    <% end %>
                  </p>
                </div>
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Frequency</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= get_frequency(@venue) %></p>
                </div>
              </div>
            </div>

            <!-- Description -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <h2 class="mb-4 text-xl font-bold text-gray-900">About This Trivia Night</h2>
              <div class="prose prose-indigo max-w-none">
                <p><%= get_venue_description(@venue) %></p>
              </div>
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
              <div class="h-64 overflow-hidden rounded-md bg-gray-200">
                <!-- Placeholder for map -->
                <div class="flex h-full w-full items-center justify-center">
                  <p class="text-gray-500">Map View</p>
                </div>
              </div>
              <div class="mt-4">
                <p class="text-gray-600"><%= @venue.address %></p>
                <a href="#" class="mt-2 inline-flex items-center text-sm font-medium text-indigo-600 hover:text-indigo-700">
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
                      <p>Starts at <%= get_start_time(@venue) %></p>
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
      Map.get(event, :start_time, "7:00 PM") # Default time if not found
    else
      # Default value if no events
      "7:00 PM"
    end
  end

  defp format_day(day) when is_integer(day) do
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

  defp format_day(_), do: "TBA"

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

  # Get venue image - updated to use the full venue instead of just the name
  defp get_venue_image(venue) do
    try do
      # First check for stored Google Place images
      if Enum.any?(venue.google_place_images) do
        TriviaAdvisor.Services.GooglePlaceImageStore.get_first_image_url(venue)
      else
        # First try Unsplash
        case UnsplashService.get_venue_image(venue.name) do
          {:ok, image_url} ->
            image_url
          {:error, _reason} ->
            # Then try to fetch and store Google Places images if venue has place_id
            if venue.place_id && venue.place_id != "" do
              case TriviaAdvisor.Services.GooglePlaceImageStore.process_venue_images(venue) do
                {:ok, updated_venue} ->
                  TriviaAdvisor.Services.GooglePlaceImageStore.get_first_image_url(updated_venue)
                _ ->
                  # Fallback to direct API call if processing fails
                  GooglePlacesService.get_venue_image(venue.id) || get_fallback_image(venue.name)
              end
            else
              # Fall back to hardcoded images
              get_fallback_image(venue.name)
            end
        end
      end
    rescue
      # If service is not started or any other error occurs
      error ->
        Logger.error("Failed to get venue image: #{inspect(error)}")
        get_fallback_image(venue.name)
    end
  end

  defp get_fallback_image(venue_name) do
    # Fallback to hardcoded image URLs
    cond do
      String.contains?(venue_name, "Pub Quiz Champion") ->
        "https://images.unsplash.com/photo-1546622891-02c72c1537b6?q=80&w=2000"
      String.contains?(venue_name, "Scholar") ->
        "https://images.unsplash.com/photo-1574096079513-d8259312b785?q=80&w=2000"
      true ->
        "https://images.unsplash.com/photo-1572116469696-31de0f17cc34?q=80&w=2000"
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

  # Check if venue has multiple Google Place images
  defp venue_has_images?(venue) do
    venue.google_place_images && is_list(venue.google_place_images) && length(venue.google_place_images) >= 5
  end

  # Get venue image at a specific position
  defp get_venue_image_at_position(venue, position) do
    if venue.google_place_images && length(venue.google_place_images) > position do
      image_data = Enum.find(venue.google_place_images, fn img -> img["position"] == position end) ||
                  Enum.at(venue.google_place_images, position)

      if image_data do
        if image_data["local_path"] do
          ensure_full_url(image_data["local_path"])
        else
          image_data["original_url"]
        end
      else
        get_fallback_image(venue.name)
      end
    else
      get_fallback_image(venue.name)
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
    if String.starts_with?(path, "http") do
      path
    else
      # Simplistic approach - in a real app use your app's URL config
      "#{TriviaAdvisorWeb.Endpoint.url()}#{path}"
    end
  end
end

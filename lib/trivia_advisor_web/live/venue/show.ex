defmodule TriviaAdvisorWeb.VenueLive.Show do
  use TriviaAdvisorWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # In a real app, you would fetch venue data from your database
    # For now, we'll use mock data
    venue = get_venue(id)

    {:ok,
      socket
      |> assign(:page_title, "#{venue.name} - TriviaAdvisor")
      |> assign(:venue, venue)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:id, id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Venue Hero Section -->
      <div class="relative">
        <div class="h-64 overflow-hidden sm:h-80 lg:h-96">
          <img
            src={@venue.hero_image_url || "https://placehold.co/1200x400?text=#{@venue.name}"}
            alt={@venue.name}
            class="h-full w-full object-cover"
          />
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent"></div>
        <div class="absolute bottom-0 w-full p-4 text-white sm:p-6">
          <div class="mx-auto max-w-7xl">
            <div class="flex items-center justify-between">
              <h1 class="text-3xl font-bold sm:text-4xl md:text-5xl"><%= @venue.name %></h1>
              <div class="flex gap-2">
                <button class="flex items-center gap-1 rounded-full bg-white/20 px-3 py-1 text-sm backdrop-blur-sm hover:bg-white/30">
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0 1 11.186 0Z" />
                  </svg>
                  Save
                </button>
                <button class="flex items-center gap-1 rounded-full bg-white/20 px-3 py-1 text-sm backdrop-blur-sm hover:bg-white/30">
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M7.217 10.907a2.25 2.25 0 1 0 0 2.186m0-2.186c.18.324.283.696.283 1.093s-.103.77-.283 1.093m0-2.186 9.566-5.314m-9.566 7.5 9.566 5.314m0 0a2.25 2.25 0 1 0 3.935-2.186 2.25 2.25 0 0 0-3.935-2.186zm0-12.814a2.25 2.25 0 1 0 3.933-2.185 2.25 2.25 0 0 0-3.933 2.185Z" />
                  </svg>
                  Share
                </button>
              </div>
            </div>
            <div class="mt-2 flex items-center">
              <div class="flex">
                <%= for i <- 1..5 do %>
                  <svg
                    class={"h-5 w-5 #{if i <= (@venue.rating || 0), do: "text-yellow-400", else: "text-gray-300"}"}
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                  </svg>
                <% end %>
              </div>
              <span class="ml-2 text-white/90"><%= @venue.rating %> (<%= @venue.review_count || 0 %> reviews)</span>
              <span class="mx-2">•</span>
              <span class="text-white/90"><%= @venue.address %></span>
            </div>
          </div>
        </div>
      </div>

      <div class="mx-auto max-w-7xl px-4 py-8">
        <div class="grid gap-8 md:grid-cols-3">
          <!-- Main Content -->
          <div class="md:col-span-2">
            <!-- Key Details -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <div class="mb-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Quiz Day</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= format_day(@venue.day_of_week) %></p>
                </div>
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Start Time</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= @venue.start_time %></p>
                </div>
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Entry Fee</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900">
                    <%= if @venue.entry_fee_cents do %>
                      $<%= :erlang.float_to_binary(@venue.entry_fee_cents / 100, [decimals: 2]) %>
                    <% else %>
                      Free
                    <% end %>
                  </p>
                </div>
                <div>
                  <h3 class="text-sm font-medium text-gray-500">Frequency</h3>
                  <p class="mt-1 text-lg font-semibold text-gray-900"><%= @venue.frequency || "Weekly" %></p>
                </div>
              </div>
            </div>

            <!-- Description -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <h2 class="mb-4 text-xl font-bold text-gray-900">About This Trivia Night</h2>
              <div class="prose prose-indigo max-w-none">
                <p><%= @venue.description %></p>
              </div>
            </div>

            <!-- Reviews -->
            <div class="mb-8 overflow-hidden rounded-lg border bg-white p-6 shadow-sm">
              <div class="mb-4 flex items-center justify-between">
                <h2 class="text-xl font-bold text-gray-900">Reviews</h2>
                <button class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                  Write a Review
                </button>
              </div>

              <%= if length(@venue.reviews || []) > 0 do %>
                <div class="divide-y divide-gray-200">
                  <%= for review <- @venue.reviews do %>
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
                      <%= format_day(@venue.day_of_week) %>, <%= format_next_date(@venue.day_of_week) %>
                    </h3>
                    <div class="mt-2 text-sm text-indigo-700">
                      <p>Starts at <%= @venue.start_time %></p>
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
  defp get_venue(id) do
    # This would normally come from your database
    case id do
      "1" -> %{
        id: "1",
        name: "The Pub Quiz Champion",
        address: "123 Main St, London",
        city_id: "1",
        city_name: "London",
        country_name: "United Kingdom",
        day_of_week: 4, # Thursday
        start_time: "7:30 PM",
        entry_fee_cents: 500,
        frequency: "Weekly",
        description: "Join us every Thursday for our legendary pub quiz. Six rounds of trivia, picture rounds, and music. Great prizes and a fun atmosphere! Our quizmaster has been running this quiz for over 5 years and creates challenging but fair questions across a range of topics. Teams of up to 6 people are welcome, and we recommend booking a table in advance as it gets busy.",
        hero_image_url: "https://images.unsplash.com/photo-1546622891-02c72c1537b6?q=80&w=2000",
        rating: 4.5,
        review_count: 28,
        phone: "020-1234-5678",
        website: "https://example.com/pub-quiz-champion",
        reviews: [
          %{
            user_name: "Jane Smith",
            date: "March 15, 2023",
            rating: 5,
            comment: "Amazing quiz night! The questions were challenging but fair, and the atmosphere was fantastic. Will definitely be coming back!"
          },
          %{
            user_name: "John Doe",
            date: "February 22, 2023",
            rating: 4,
            comment: "Really enjoyed the variety of questions. The music round was particularly fun. Only suggestion would be to improve the sound system."
          }
        ]
      }
      "2" -> %{
        id: "2",
        name: "Quiz Night at The Scholar",
        address: "456 High St, Manchester",
        city_id: "4",
        city_name: "Manchester",
        country_name: "United Kingdom",
        day_of_week: 2, # Tuesday
        start_time: "8:00 PM",
        entry_fee_cents: 300,
        frequency: "Weekly",
        description: "Tuesday night is quiz night! Form teams of up to 6 people and test your knowledge across a variety of categories. Our quizzes feature general knowledge, sports, entertainment, and special themed rounds that change every week.",
        hero_image_url: "https://images.unsplash.com/photo-1574096079513-d8259312b785?q=80&w=2000",
        rating: 4.2,
        review_count: 15,
        phone: "0161-987-6543",
        website: "https://example.com/scholar-pub",
        reviews: []
      }
      _ -> %{
        id: id,
        name: "Unknown Venue",
        address: "Unknown Address",
        city_id: nil,
        city_name: "Unknown City",
        country_name: "Unknown Country",
        day_of_week: nil,
        start_time: nil,
        entry_fee_cents: nil,
        frequency: nil,
        description: "No information available for this venue.",
        hero_image_url: nil,
        rating: nil,
        review_count: 0,
        phone: nil,
        website: nil,
        reviews: []
      }
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
end

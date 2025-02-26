defmodule TriviaAdvisorWeb.CityLive.Show do
  use TriviaAdvisorWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # In a real app, you would fetch city and venue data from your database
    # For now, we'll use mock data
    {:ok,
      socket
      |> assign(:page_title, "City Details")
      |> assign(:city, get_city(id))
      |> assign(:venues, get_venues_for_city(id))}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "#{socket.assigns.city.name} - Trivia Venues")
     |> assign(:id, id)}
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

      <div class="mx-auto max-w-7xl px-4 py-8">
        <div class="mb-8">
          <h2 class="text-2xl font-bold text-gray-900">Trivia Venues in <%= @city.name %></h2>
          <p class="mt-2 text-gray-600">Discover the best pub quizzes and trivia nights in <%= @city.name %>.</p>
        </div>

        <!-- Venue List -->
        <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <%= for venue <- @venues do %>
            <div class="flex flex-col overflow-hidden rounded-lg border bg-white shadow">
              <div class="relative h-48 overflow-hidden">
                <img
                  src={venue.hero_image_url || "https://placehold.co/600x400?text=#{venue.name}"}
                  alt={venue.name}
                  class="h-full w-full object-cover"
                />

                <!-- Entry fee badge -->
                <%= if venue.entry_fee_cents do %>
                  <div class="absolute right-2 top-2 rounded-full bg-indigo-600 px-2 py-1 text-xs font-medium text-white">
                    $<%= :erlang.float_to_binary(venue.entry_fee_cents / 100, [decimals: 2]) %>
                  </div>
                <% else %>
                  <div class="absolute right-2 top-2 rounded-full bg-green-600 px-2 py-1 text-xs font-medium text-white">
                    Free
                  </div>
                <% end %>
              </div>

              <div class="flex flex-1 flex-col p-4">
                <h3 class="mb-1 text-lg font-semibold text-gray-900">
                  <a href={~p"/venues/#{venue.id}"} class="hover:text-indigo-600"><%= venue.name %></a>
                </h3>

                <div class="mb-2 flex items-center text-sm text-gray-600">
                  <svg class="mr-1 h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M9.69 18.933l.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 00.281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 103 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 002.273 1.765 11.842 11.842 0 00.976.544l.062.029.018.008.006.003zM10 11.25a2.25 2.25 0 100-4.5 2.25 2.25 0 000 4.5z" clip-rule="evenodd" />
                  </svg>
                  <span><%= venue.address %></span>
                </div>

                <p class="mb-4 flex-1 text-sm text-gray-600 line-clamp-3">
                  <%= venue.description %>
                </p>

                <div class="mt-auto flex items-center justify-between">
                  <div class="flex">
                    <%= for i <- 1..5 do %>
                      <svg
                        class={"h-4 w-4 #{if i <= (venue.rating || 0), do: "text-yellow-400", else: "text-gray-300"}"}
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                      >
                        <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                      </svg>
                    <% end %>
                  </div>
                  <span class="text-sm text-gray-600">
                    <%= format_day(venue.day_of_week) %> at <%= venue.start_time %>
                  </span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Mock data functions for demonstration
  defp get_city(id) do
    # This would normally come from your database
    case id do
      "1" -> %{
        id: "1",
        name: "London",
        country_name: "United Kingdom",
        venue_count: 120,
        image_url: "https://images.unsplash.com/photo-1533929736458-ca588d08c8be?q=80&w=2000"
      }
      "2" -> %{
        id: "2",
        name: "New York",
        country_name: "United States",
        venue_count: 87,
        image_url: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?q=80&w=2000"
      }
      "3" -> %{
        id: "3",
        name: "Sydney",
        country_name: "Australia",
        venue_count: 45,
        image_url: "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?q=80&w=2000"
      }
      _ -> %{
        id: id,
        name: "Unknown City",
        country_name: "Unknown Country",
        venue_count: 0,
        image_url: nil
      }
    end
  end

  defp get_venues_for_city(city_id) do
    # This would normally come from your database
    case city_id do
      "1" -> [
        %{
          id: "1",
          name: "The Pub Quiz Champion",
          address: "123 Main St, London",
          day_of_week: 4, # Thursday
          start_time: "7:30 PM",
          entry_fee_cents: 500,
          description: "Join us every Thursday for our legendary pub quiz. Six rounds of trivia, picture rounds, and music. Great prizes and a fun atmosphere!",
          hero_image_url: "https://images.unsplash.com/photo-1546622891-02c72c1537b6?q=80&w=2000",
          rating: 4.5
        },
        %{
          id: "5",
          name: "The Crown Trivia",
          address: "22 Queen's Road, London",
          day_of_week: 2, # Tuesday
          start_time: "8:00 PM",
          entry_fee_cents: 300,
          description: "A lively pub quiz with a focus on pop culture, sports, and general knowledge. Cash prizes and fun guaranteed!",
          hero_image_url: "https://images.unsplash.com/photo-1566633806327-68e152aaf26d?q=80&w=2000",
          rating: 4.0
        },
        %{
          id: "6",
          name: "Quiz & Pint",
          address: "54 Camden High Street, London",
          day_of_week: 3, # Wednesday
          start_time: "7:00 PM",
          entry_fee_cents: nil,
          description: "Free entry quiz with 5 rounds of challenging questions. Special drink deals for all participants!",
          hero_image_url: "https://images.unsplash.com/photo-1600431521340-491eca880813?q=80&w=2000",
          rating: 4.3
        }
      ]
      "2" -> [
        %{
          id: "7",
          name: "NYC Trivia Kings",
          address: "420 Broadway, New York",
          day_of_week: 2, # Tuesday
          start_time: "8:00 PM",
          entry_fee_cents: 400,
          description: "New York's favorite trivia night with NYC-themed questions and regular challenges.",
          hero_image_url: "https://images.unsplash.com/photo-1574096079513-d8259312b785?q=80&w=2000",
          rating: 4.7
        },
        %{
          id: "8",
          name: "Brooklyn Quiz Co.",
          address: "67 Williamsburg Ave, New York",
          day_of_week: 4, # Thursday
          start_time: "7:30 PM",
          entry_fee_cents: 500,
          description: "Hipster trivia with craft beer pairings and local Brooklyn-themed questions.",
          hero_image_url: "https://images.unsplash.com/photo-1546622891-02c72c1537b6?q=80&w=2000",
          rating: 4.2
        }
      ]
      "3" -> [
        %{
          id: "9",
          name: "Aussie Trivia Masters",
          address: "32 Bondi Road, Sydney",
          day_of_week: 3, # Wednesday
          start_time: "7:00 PM",
          entry_fee_cents: 1000,
          description: "The ultimate Australian trivia experience with questions about local culture, sports, and history.",
          hero_image_url: "https://images.unsplash.com/photo-1600431521340-491eca880813?q=80&w=2000",
          rating: 4.6
        }
      ]
      _ -> []
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
end

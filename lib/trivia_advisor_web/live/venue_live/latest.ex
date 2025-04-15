defmodule TriviaAdvisorWeb.VenueLive.Latest do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisorWeb.Components.UI.VenueCard

  @impl true
  def mount(_params, _session, socket) do
    # Get more venues for this page - using the existing function but with higher limit
    latest_venues = TriviaAdvisor.Locations.get_featured_venues(limit: 24)

    # Group venues by week (based on inserted_at timestamp)
    venues_by_week = group_venues_by_week(latest_venues)

    {:ok, assign(socket,
      page_title: "Latest Venues - QuizAdvisor",
      latest_venues: latest_venues,
      venues_by_week: venues_by_week
    )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 md:px-8">
      <div class="mb-8">
        <div class="mb-4">
          <nav class="flex mb-4" aria-label="Breadcrumb">
            <ol class="inline-flex items-center space-x-1 md:space-x-3">
              <li class="inline-flex items-center">
                <a href="/" class="inline-flex items-center text-sm font-medium text-gray-700 hover:text-indigo-600">
                  <svg class="w-3 h-3 mr-2.5" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 20 20">
                    <path d="m19.707 9.293-2-2-7-7a1 1 0 0 0-1.414 0l-7 7-2 2a1 1 0 0 0 1.414 1.414L2 10.414V18a2 2 0 0 0 2 2h3a1 1 0 0 0 1-1v-4a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v4a1 1 0 0 0 1 1h3a2 2 0 0 0 2-2v-7.586l.293.293a1 1 0 0 0 1.414-1.414Z"/>
                  </svg>
                  Home
                </a>
              </li>
              <li aria-current="page">
                <div class="flex items-center">
                  <svg class="w-3 h-3 text-gray-400 mx-1" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 6 10">
                    <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m1 9 4-4-4-4"/>
                  </svg>
                  <span class="ml-1 text-sm font-medium text-gray-500 md:ml-2">Latest Venues</span>
                </div>
              </li>
            </ol>
          </nav>
        </div>
        <h1 class="text-3xl font-bold text-gray-900">Latest Venues</h1>
        <p class="mt-2 text-gray-600">Discover the newest pub quizzes and trivia venues added to QuizAdvisor</p>
      </div>

      <%= if length(@latest_venues) > 0 do %>
        <%= for {period, venues} <- @venues_by_week do %>
          <div class="mb-12">
            <h2 class="mb-4 text-xl font-semibold text-gray-900 border-b pb-2">
              <%= format_time_period(period) %>
            </h2>
            <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              <%= for venue <- venues do %>
                <VenueCard.venue_card venue={venue} />
              <% end %>
            </div>
          </div>
        <% end %>
      <% else %>
        <div class="bg-white p-8 rounded-lg shadow-sm text-center">
          <p class="text-gray-600">No new venues have been added recently. Check back soon!</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Group venues by week based on their inserted_at timestamp
  defp group_venues_by_week(venues) do
    venues
    |> Enum.group_by(fn venue ->
      date = venue.inserted_at || DateTime.utc_now()
      # Get start of the week (Monday)
      monday = Date.beginning_of_week(date)
      # Get end of the week (Sunday)
      sunday = Date.add(monday, 6)
      {monday, sunday}
    end)
    |> Enum.sort_by(fn {{start_date, _end_date}, _venues} -> start_date end, {:desc, Date})
  end

  # Format the time period for display
  defp format_time_period({start_date, end_date}) do
    start_formatted = Calendar.strftime(start_date, "%b %d, %Y")
    end_formatted = Calendar.strftime(end_date, "%b %d, %Y")
    "#{start_formatted} - #{end_formatted}"
  end
end

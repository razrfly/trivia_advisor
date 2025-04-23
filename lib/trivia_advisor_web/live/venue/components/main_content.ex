defmodule TriviaAdvisorWeb.Live.Venue.Components.MainContent do
  @moduledoc """
  Main content components for the Venue Show page.
  """
  use TriviaAdvisorWeb, :live_component

  alias TriviaAdvisorWeb.Live.Venue.Helpers.VenueShowHelpers
  import VenueShowHelpers
  import TriviaAdvisorWeb.Helpers.FormatHelpers, only: [
    has_event_source?: 1,
    format_last_updated: 1,
    format_active_since: 1,
    get_source_name: 1
  ]
  import TriviaAdvisorWeb.Helpers.LocalizationHelpers, only: [format_localized_time: 2]
  require Logger

  def render(assigns) do
    ~H"""
    <div>
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
                    src={get_venue_image(venue_info.venue)}
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
    """
  end
end

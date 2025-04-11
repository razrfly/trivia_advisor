defmodule TriviaAdvisorWeb.Live.Venue.Components.Sidebar do
  @moduledoc """
  Sidebar components for the Venue Show page.
  """
  use TriviaAdvisorWeb, :live_component

  alias TriviaAdvisorWeb.Live.Venue.Helpers.VenueShowHelpers
  import VenueShowHelpers
  import TriviaAdvisorWeb.Helpers.LocalizationHelpers, only: [format_localized_time: 2]
  require Logger

  def render(assigns) do
    ~H"""
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
    """
  end
end

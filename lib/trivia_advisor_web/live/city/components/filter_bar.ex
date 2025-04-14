defmodule TriviaAdvisorWeb.CityLive.Components.FilterBar do
  @moduledoc """
  Filter component for city pages to handle radius selection and suburb filtering.
  """
  use TriviaAdvisorWeb, :live_component

  @doc """
  Renders the filter bar with radius selector and suburb filters.

  ## Assigns
    * id - Component ID
    * radius - Current selected radius
    * radius_options - List of radius options as {label, value} tuples
    * selected_suburbs - List of selected suburb IDs
    * suburbs - List of available suburbs with their data
  """
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-8 flex flex-wrap items-center justify-between gap-4">
        <h2 class="text-2xl font-bold text-gray-900">Trivia Venues in <%= @city.name %></h2>

        <div class="flex items-center gap-3">
          <label for="radius" class="text-sm font-medium text-gray-700">Search radius:</label>
          <form phx-change="change-radius" class="flex items-center">
            <select
              id="radius"
              name="radius"
              class="rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
              value={@radius}
            >
              <%= for {label, value} <- @radius_options do %>
                <option value={value} selected={value == @radius}><%= label %></option>
              <% end %>
            </select>
          </form>
        </div>
      </div>

      <p class="mb-4 text-lg text-gray-600">
        Discover the best pub quizzes and trivia nights near <%= @city.name %>.
        <%= if @radius != 0 do %>
          Showing venues within <%= @radius %> km.
        <% end %>
      </p>

      <%= if length(@suburbs) > 0 do %>
        <div class="mb-6">
          <div class="flex justify-between items-center mb-3">
            <h3 class="text-sm font-medium text-gray-700">Filter by suburb:</h3>
            <%= if length(@selected_suburbs) > 0 do %>
              <button
                phx-click="clear-suburbs"
                class="text-sm text-indigo-600 hover:text-indigo-800"
              >
                Clear filters
              </button>
            <% end %>
          </div>

          <div class="flex flex-wrap gap-2">
            <%= for suburb <- @suburbs do %>
              <% is_selected = suburb.city.id in @selected_suburbs %>
              <%= if is_selected do %>
                <button
                  phx-click="remove-suburb"
                  phx-value-suburb-id={suburb.city.id}
                  class="inline-flex items-center rounded-full bg-indigo-100 py-1.5 pl-3 pr-2 text-sm font-medium text-indigo-700 hover:bg-indigo-200"
                >
                  <%= suburb.city.name %> (<%= suburb.venue_count %>)
                  <span class="ml-1 inline-flex h-4 w-4 flex-shrink-0 items-center justify-center rounded-full text-indigo-500 hover:bg-indigo-200 hover:text-indigo-600">
                    <svg class="h-2.5 w-2.5" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
                      <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z"></path>
                    </svg>
                  </span>
                </button>
              <% else %>
                <button
                  phx-click="select-suburb"
                  phx-value-suburb-id={suburb.city.id}
                  class="inline-flex items-center rounded-full bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-800 hover:bg-gray-200"
                >
                  <%= suburb.city.name %> (<%= suburb.venue_count %>)
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

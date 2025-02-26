defmodule TriviaAdvisorWeb.Components.UI.CitySearch do
  use TriviaAdvisorWeb, :live_component

  def render(assigns) do
    ~H"""
    <div id={@id} class="relative w-full" phx-hook="CitySearch">
      <div class="relative">
        <input
          type="text"
          id={@id <> "-input"}
          class="w-full rounded-lg border border-gray-300 px-4 py-3 pl-10 text-sm shadow-sm focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
          placeholder="Search for a city..."
          phx-keyup="search"
          phx-debounce="300"
          phx-target={@myself}
          value={@query}
          autocomplete="off"
        />
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
          <svg class="h-5 w-5 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11zM2 9a7 7 0 1112.452 4.391l3.328 3.329a.75.75 0 11-1.06 1.06l-3.329-3.328A7 7 0 012 9z" clip-rule="evenodd" />
          </svg>
        </div>
      </div>

      <%= if @show_results and length(@results) > 0 do %>
        <div class="absolute z-10 mt-1 w-full rounded-md border border-gray-200 bg-white py-1 shadow-lg">
          <ul class="max-h-60 overflow-auto py-1 text-base">
            <%= for city <- @results do %>
              <li
                class="cursor-pointer px-4 py-2 hover:bg-indigo-50"
                phx-click="select-city"
                phx-value-id={city.id}
                phx-value-name={city.name}
                phx-target={@myself}
              >
                <div class="flex items-center">
                  <div class="ml-3">
                    <p class="text-sm font-medium text-gray-900"><%= city.name %></p>
                    <p class="text-xs text-gray-500"><%= city.country_name %></p>
                  </div>
                </div>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end

  def mount(socket) do
    {:ok,
      socket
      |> assign(:query, "")
      |> assign(:results, [])
      |> assign(:show_results, false)}
  end

  def update(assigns, socket) do
    {:ok,
      socket
      |> assign(assigns)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:results, fn -> [] end)
      |> assign_new(:show_results, fn -> false end)}
  end

  def handle_event("search", %{"value" => query}, socket) when byte_size(query) < 2 do
    {:noreply,
      socket
      |> assign(:query, query)
      |> assign(:results, [])
      |> assign(:show_results, false)}
  end

  def handle_event("search", %{"value" => query}, socket) do
    # In a real app, you would search the database for cities
    # For now, we'll use mock data
    results = search_cities(query)

    {:noreply,
      socket
      |> assign(:query, query)
      |> assign(:results, results)
      |> assign(:show_results, true)}
  end

  def handle_event("select-city", %{"id" => id, "name" => name}, socket) do
    # Send the selected city to the parent
    send(self(), {:city_selected, %{id: id, name: name}})

    {:noreply,
      socket
      |> assign(:query, name)
      |> assign(:show_results, false)}
  end

  # Mock function to search cities - this would normally query your database
  defp search_cities(query) do
    # Mock city data for demonstration
    [
      %{id: "1", name: "London", country_name: "United Kingdom"},
      %{id: "2", name: "New York", country_name: "United States"},
      %{id: "3", name: "Paris", country_name: "France"},
      %{id: "4", name: "Tokyo", country_name: "Japan"},
      %{id: "5", name: "Sydney", country_name: "Australia"},
      %{id: "6", name: "Berlin", country_name: "Germany"},
      %{id: "7", name: "Rome", country_name: "Italy"},
      %{id: "8", name: "Madrid", country_name: "Spain"},
      %{id: "9", name: "Toronto", country_name: "Canada"},
      %{id: "10", name: "Amsterdam", country_name: "Netherlands"}
    ]
    |> Enum.filter(fn city ->
      String.contains?(String.downcase(city.name), String.downcase(query)) or
      String.contains?(String.downcase(city.country_name), String.downcase(query))
    end)
    |> Enum.take(5)  # Limit to 5 results
  end
end

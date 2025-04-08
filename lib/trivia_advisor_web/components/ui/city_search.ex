defmodule TriviaAdvisorWeb.Components.UI.CitySearch do
  use TriviaAdvisorWeb, :live_component
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.City
  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
    <div id={@id} class="relative w-full">
      <div class="relative">
        <form phx-change="search" phx-target={@myself}>
          <input
            type="text"
            id={@id <> "-input"}
            name="query"
            class="w-full rounded-lg border border-gray-300 px-4 py-3 pl-10 text-sm text-gray-900 shadow-sm focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            placeholder="Search for a city..."
            value={@query}
            phx-click-away={JS.hide(to: "##{@id}-results")}
            phx-window-keydown={JS.hide(to: "##{@id}-results")}
            phx-key="escape"
            autocomplete="off"
          />
        </form>
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
          <svg class="h-5 w-5 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11zM2 9a7 7 0 1112.452 4.391l3.328 3.329a.75.75 0 11-1.06 1.06l-3.329-3.328A7 7 0 012 9z" clip-rule="evenodd" />
          </svg>
        </div>
      </div>

      <div
        id={@id <> "-results"}
        class="absolute z-10 mt-1 w-full rounded-md border border-gray-200 bg-white py-1 shadow-lg"
        style={if @show_results and length(@results) > 0, do: "", else: "display: none;"}
      >
        <ul class="max-h-60 overflow-auto py-1 text-base">
          <%= for city <- @results do %>
            <li
              class="cursor-pointer px-4 py-2 hover:bg-indigo-50 text-left"
              phx-click="select-city"
              phx-value-id={city.id}
              phx-value-name={city.name}
              phx-target={@myself}
            >
              <p class="text-sm font-medium text-gray-900"><%= city.name %></p>
              <p class="text-xs text-gray-500"><%= city.country_name %></p>
            </li>
          <% end %>
        </ul>
      </div>
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

  def handle_event("search", %{"query" => query}, socket) do
    # Only search if query is at least 2 characters
    {results, show_results} =
      if byte_size(query) >= 2 do
        results = search_cities(query)
        {results, length(results) > 0}
      else
        {[], false}
      end

    {:noreply,
      socket
      |> assign(:query, query)
      |> assign(:results, results)
      |> assign(:show_results, show_results)}
  end

  def handle_event("select-city", %{"id" => id, "name" => name}, socket) do
    IO.inspect({id, name}, label: "SELECTED CITY")

    # Get the selected city from results to include all data (including slug)
    selected_city = Enum.find(socket.assigns.results, fn city ->
      city.id == id && city.name == name
    end)

    # Fallback to basic data if not found in results - use database lookup
    city_data = if selected_city do
      selected_city
    else
      # Try to fetch from database by ID
      case TriviaAdvisor.Repo.get(TriviaAdvisor.Locations.City, id) do
        nil ->
          # Generate a proper slug if we can't find the city in DB
          slug = name
                |> String.downcase()
                |> String.replace(~r/\s+/, "-")
                |> String.replace(~r/[^a-z0-9\-]/, "")
          %{id: id, name: name, slug: slug}
        city ->
          # Use the actual database slug
          %{id: city.id, name: city.name, slug: city.slug}
      end
    end

    # Send the selected city to the parent
    send(self(), {:city_selected, city_data})

    {:noreply,
      socket
      |> assign(:query, name)
      |> assign(:show_results, false)}
  end

  # Search cities in the database
  defp search_cities(query) do
    IO.inspect(query, label: "SEARCHING DATABASE FOR")

    from(c in City,
      join: co in assoc(c, :country),
      where: ilike(c.name, ^"%#{query}%") or ilike(co.name, ^"%#{query}%"),
      select: %{
        id: c.id,
        name: c.name,
        country_name: co.name,
        slug: c.slug
      },
      order_by: [asc: c.name],
      limit: 5
    )
    |> Repo.all()
    |> then(fn results ->
      IO.inspect(results, label: "SEARCH RESULTS")
      results
    end)
  end
end

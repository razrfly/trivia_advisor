defmodule TriviaAdvisorWeb.DevLive.Cache do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisor.Services.UnsplashService
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Cache Management")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <h1 class="text-2xl font-bold text-gray-900 mb-6">Image Cache Management</h1>

      <div class="bg-white rounded-lg shadow overflow-hidden mb-8">
        <div class="p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">Clear Cache</h2>
          <p class="text-gray-600 mb-4">Clear the Unsplash image cache to force fetching fresh images from the API.</p>

          <div class="space-y-4">
            <div>
              <button
                phx-click="clear-all-cache"
                class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
              >
                Clear All Cache
              </button>
              <p class="mt-1 text-sm text-gray-500">Removes all cached images</p>
            </div>

            <div class="mt-6">
              <h3 class="text-md font-medium text-gray-900 mb-2">Clear City Image</h3>
              <div class="flex gap-4">
                <div>
                  <form phx-submit="clear-city-cache" class="flex gap-2">
                    <input
                      type="text"
                      name="city_name"
                      placeholder="City name"
                      required
                      class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
                    />
                    <button
                      type="submit"
                      class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      Clear
                    </button>
                  </form>
                </div>
              </div>
            </div>

            <div class="mt-6">
              <h3 class="text-md font-medium text-gray-900 mb-2">Clear Venue Image</h3>
              <div class="flex gap-4">
                <div>
                  <form phx-submit="clear-venue-cache" class="flex gap-2">
                    <input
                      type="text"
                      name="venue_name"
                      placeholder="Venue name"
                      required
                      class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
                    />
                    <button
                      type="submit"
                      class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      Clear
                    </button>
                  </form>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="mt-8 bg-white rounded-lg shadow overflow-hidden">
        <div class="p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">Popular Pages</h2>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <a
              href="/"
              class="block p-4 border rounded-lg hover:bg-gray-50"
            >
              <h3 class="font-medium text-gray-900">Home</h3>
              <p class="mt-1 text-sm text-gray-500">Return to the home page</p>
            </a>

            <a
              href="/cities/london"
              class="block p-4 border rounded-lg hover:bg-gray-50"
            >
              <h3 class="font-medium text-gray-900">London</h3>
              <p class="mt-1 text-sm text-gray-500">View London city page</p>
            </a>

            <a
              href="/cities/new-york"
              class="block p-4 border rounded-lg hover:bg-gray-50"
            >
              <h3 class="font-medium text-gray-900">New York</h3>
              <p class="mt-1 text-sm text-gray-500">View New York city page</p>
            </a>

            <a
              href="/venues/1"
              class="block p-4 border rounded-lg hover:bg-gray-50"
            >
              <h3 class="font-medium text-gray-900">Pub Quiz Champion</h3>
              <p class="mt-1 text-sm text-gray-500">View venue page</p>
            </a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("clear-all-cache", _params, socket) do
    UnsplashService.clear_cache()
    {:noreply, put_flash(socket, :info, "All image cache cleared successfully")}
  end

  @impl true
  def handle_event("clear-city-cache", %{"city_name" => city_name}, socket) when city_name != "" do
    case UnsplashService.clear_cache("city", city_name) do
      :ok -> {:noreply, put_flash(socket, :info, "Cache for city '#{city_name}' cleared successfully")}
      :not_found -> {:noreply, put_flash(socket, :info, "No cached image found for city '#{city_name}'")}
    end
  end

  @impl true
  def handle_event("clear-venue-cache", %{"venue_name" => venue_name}, socket) when venue_name != "" do
    case UnsplashService.clear_cache("venue", venue_name) do
      :ok -> {:noreply, put_flash(socket, :info, "Cache for venue '#{venue_name}' cleared successfully")}
      :not_found -> {:noreply, put_flash(socket, :info, "No cached image found for venue '#{venue_name}'")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    Logger.warning("Unhandled event: #{event}, params: #{inspect(params)}")
    {:noreply, socket}
  end
end

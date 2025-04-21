defmodule TriviaAdvisorWeb.DevLive.Cache do
  use TriviaAdvisorWeb, :live_view
  alias TriviaAdvisor.Services.UnsplashService
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "Cache Management",
      cache_cleared: false,
      latest_venues_cleared: false
    )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 md:px-8">
      <h1 class="text-3xl font-bold mb-6">Cache Management</h1>

      <div class="bg-white rounded-lg shadow-sm p-6 mb-6">
        <h2 class="text-xl font-semibold mb-4">Latest Venues Cache</h2>
        <p class="mb-4">Clear only the Latest Venues cache to force a fresh lookup of the most recently added venues.</p>

        <button phx-click="clear-latest-venues-cache" class="bg-yellow-500 hover:bg-yellow-600 text-white font-semibold py-2 px-4 rounded">
          Clear Latest Venues Cache
        </button>

        <%= if @latest_venues_cleared do %>
          <p class="mt-4 text-green-600 font-semibold">Latest Venues cache cleared successfully!</p>
        <% end %>
      </div>

      <div class="bg-white rounded-lg shadow-sm p-6">
        <h2 class="text-xl font-semibold mb-4">Global Cache</h2>
        <p class="mb-4">Warning: This will clear all cached data in the application. Use with caution!</p>

        <button phx-click="clear-all-cache" class="bg-red-500 hover:bg-red-600 text-white font-semibold py-2 px-4 rounded">
          Clear All Cached Data
        </button>

        <%= if @cache_cleared do %>
          <p class="mt-4 text-green-600 font-semibold">Cache cleared successfully!</p>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("clear-all-cache", _params, socket) do
    TriviaAdvisor.Cache.clear()
    {:noreply, assign(socket, cache_cleared: true)}
  end

  @impl true
  def handle_event("clear-latest-venues-cache", _params, socket) do
    # Clear only the latest venues cache entries
    clear_latest_venues_cache()
    {:noreply, assign(socket, latest_venues_cleared: true)}
  end

  defp clear_latest_venues_cache do
    # This function selectively clears only the cache entries for latest venues
    # The key format is "latest_venues:limit:X" where X is the limit
    # We'll try to clear entries with common limits
    [4, 24, 72]
    |> Enum.each(fn limit ->
      key = "latest_venues:limit:#{limit}"
      case :ets.lookup(:trivia_advisor_cache, key) do
        [] ->
          # Key not found, do nothing
          nil
        _entry ->
          # Key found, delete it
          :ets.delete(:trivia_advisor_cache, key)
      end

      # Also clear diverse latest venues cache
      diverse_key = "diverse_latest_venues:limit:#{limit}"
      case :ets.lookup(:trivia_advisor_cache, diverse_key) do
        [] ->
          # Key not found, do nothing
          nil
        _entry ->
          # Key found, delete it
          :ets.delete(:trivia_advisor_cache, diverse_key)
      end
    end)
  end

  @impl true
  def handle_event("clear-city-cache", %{"city_name" => city_name}, socket) when city_name != "" do
    UnsplashService.clear_cache("city", city_name)
    {:noreply, put_flash(socket, :info, "Cache for city '#{city_name}' cleared successfully")}
  end

  @impl true
  def handle_event("clear-venue-cache", %{"venue_name" => venue_name}, socket) when venue_name != "" do
    UnsplashService.clear_cache("venue", venue_name)
    {:noreply, put_flash(socket, :info, "Cache for venue '#{venue_name}' cleared successfully")}
  end

  @impl true
  def handle_event(event, params, socket) do
    Logger.warning("Unhandled event: #{event}, params: #{inspect(params)}")
    {:noreply, socket}
  end
end

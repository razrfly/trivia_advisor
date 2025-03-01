defmodule TriviaAdvisor.Services.UnsplashService do
  @moduledoc """
  Service for fetching images from Unsplash API and caching them.
  """

  use GenServer
  require Logger

  @default_cache_ttl 86_400 # 24 hours in seconds
  @table_name :unsplash_image_cache

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Get an image URL for a city, either from cache or from Unsplash API.
  """
  def get_city_image(city_name) do
    case lookup_cache(cache_key("city", city_name)) do
      {:ok, url} ->
        url
      :not_found ->
        GenServer.call(__MODULE__, {:fetch_image, "city", city_name})
    end
  end

  @doc """
  Get an image URL for a venue, either from cache or from Unsplash API.
  """
  def get_venue_image(venue_name) do
    case lookup_cache(cache_key("venue", venue_name)) do
      {:ok, url} ->
        url
      :not_found ->
        GenServer.call(__MODULE__, {:fetch_image, "venue", venue_name})
    end
  end

  @doc """
  Clear the entire image cache or clear cache for a specific type and name.
  """
  def clear_cache() do
    GenServer.call(__MODULE__, :clear_all_cache)
  end

  def clear_cache(type, name) do
    GenServer.call(__MODULE__, {:clear_cache, cache_key(type, name)})
  end

  # Server callbacks

  @impl true
  def init(_) do
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:fetch_city_image, city_name}, _from, state) do
    # For backwards compatibility
    url = fetch_from_unsplash("city", city_name)
    cache_result(cache_key("city", city_name), url)
    {:reply, url, state}
  end

  @impl true
  def handle_call({:fetch_image, type, name}, _from, state) do
    url = fetch_from_unsplash(type, name)
    cache_result(cache_key(type, name), url)
    {:reply, url, state}
  end

  @impl true
  def handle_call(:clear_all_cache, _from, state) do
    case :ets.info(@table_name) do
      :undefined ->
        Logger.info("Cache table doesn't exist, nothing to clear")
      _ ->
        :ets.delete_all_objects(@table_name)
        Logger.info("Cleared all cached images")
    end
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:clear_cache, key}, _from, state) do
    case :ets.lookup(@table_name, key) do
      [{^key, _, _}] ->
        :ets.delete(@table_name, key)
        Logger.info("Cleared cache for key: #{key}")
        {:reply, :ok, state}
      [] ->
        Logger.info("No cached item found for key: #{key}")
        {:reply, :not_found, state}
    end
  end

  # Private functions

  defp lookup_cache(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if :os.system_time(:seconds) < expires_at do
          {:ok, value}
        else
          # Expired entry
          :ets.delete(@table_name, key)
          :not_found
        end
      [] -> :not_found
    end
  end

  defp cache_result(key, value) do
    expires_at = :os.system_time(:seconds) + @default_cache_ttl
    :ets.insert(@table_name, {key, value, expires_at})
  end

  defp cache_key(type, name) do
    "#{type}_image:#{String.downcase(name)}"
  end

  defp fetch_from_unsplash(type, name) do
    # Get API key from environment
    case System.get_env("UNSPLASH_ACCESS_KEY") do
      nil ->
        Logger.warning("UNSPLASH_ACCESS_KEY not set. Using fallback image.")
        fallback_image(name)
      access_key ->
        # Customize search query based on type
        query = case type do
          "city" -> "#{name} city"
          "venue" -> "#{name} pub bar interior"
          _ -> "#{name}"
        end

        # Use search endpoint instead of random for more relevant results
        url = "https://api.unsplash.com/search/photos?query=#{URI.encode(query)}&orientation=landscape&per_page=30&client_id=#{access_key}"

        Logger.info("Fetching #{type} image from Unsplash for #{name}")

        case HTTPoison.get(url, [], [follow_redirect: true]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, data} ->
                # Get the first result, or a random one from top results
                results = Map.get(data, "results", [])

                if length(results) > 0 do
                  # Order by likes and randomly select from top 5
                  results_by_likes = Enum.sort_by(results, fn r -> Map.get(r, "likes", 0) end, :desc)

                  result = if length(results_by_likes) >= 5 do
                    Enum.random(Enum.take(results_by_likes, 5))
                  else
                    Enum.random(results_by_likes)
                  end

                  get_in(result, ["urls", "regular"]) || fallback_image(name)
                else
                  Logger.warning("No image results for #{name}")
                  fallback_image(name)
                end
              _ ->
                Logger.error("Failed to parse Unsplash API response")
                fallback_image(name)
            end
          error ->
            Logger.error("Unsplash API request failed: #{inspect(error)}")
            fallback_image(name)
        end
    end
  end

  defp fallback_image(name) do
    # Return a default image based on the first letter of the name
    # This ensures we always have somewhat different images even when API fails
    letter = String.downcase(String.first(name)) |> String.to_charlist() |> hd()
    seed = rem(letter - 97, 5) + 1  # a-e: 1, f-j: 2, k-o: 3, p-t: 4, u-z: 5

    case seed do
      1 -> "https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=1200"
      2 -> "https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=1200"
      3 -> "https://images.unsplash.com/photo-1444723121867-7a241cacace9?w=1200"
      4 -> "https://images.unsplash.com/photo-1449824913935-59a10b8d2000?w=1200"
      _ -> "https://images.unsplash.com/photo-1514924013411-cbf25faa35bb?w=1200"
    end
  end
end

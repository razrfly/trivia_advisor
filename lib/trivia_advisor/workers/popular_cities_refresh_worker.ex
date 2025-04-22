defmodule TriviaAdvisor.Workers.PopularCitiesRefreshWorker do
  @moduledoc """
  Oban worker that refreshes the popular cities cache.

  This worker is dedicated to refreshing the popular cities cache
  without recursion issues with the DailyRecalibrateWorker.
  """

  use Oban.Worker, queue: :default, max_attempts: 3
  require Logger
  import Ecto.Query

  @impl Oban.Worker
  def perform(%{id: job_id}) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting popular cities cache refresh...")

    cache_popular_cities()

    duration_ms = System.monotonic_time(:millisecond) - start_time
    Logger.info("Popular cities cache refresh completed in #{duration_ms}ms")

    # Update job metadata
    TriviaAdvisor.Repo.update_all(
      from(j in "oban_jobs", where: j.id == ^job_id),
      set: [meta: %{duration_ms: duration_ms}]
    )

    :ok
  end

  # Cache popular cities for each common parameter combination
  defp cache_popular_cities do
    Logger.info("Caching popular cities combinations")

    # Cache various combinations of parameters
    [true, false]
    |> Enum.each(fn diverse ->
      [15, 10, 6]
      |> Enum.each(fn limit ->
        [50, 30]
        |> Enum.each(fn distance ->
          cache_city_combination(limit: limit, distance_threshold: distance, diverse_countries: diverse)
        end)
      end)
    end)

    # Always cache the default combination as fallback
    store_fallback_popular_cities()

    Logger.info("Completed caching popular cities")
  end

  # Cache a specific combination of parameters
  defp cache_city_combination(opts) do
    cache_key = "popular_cities:#{inspect(opts)}"

    try do
      # Calculate popular cities
      cities = TriviaAdvisor.Locations.do_get_popular_cities(opts)

      # Store in cache with 24hr TTL
      TriviaAdvisor.Cache.store(cache_key, cities, 86400)

      Logger.info("Cached popular cities for #{inspect(opts)}")
    rescue
      e ->
        # Log error and continue with other combinations
        Logger.error("Failed to cache popular cities for #{inspect(opts)}: #{inspect(e)}")
    end
  end

  # Store fallback popular cities in cache
  defp store_fallback_popular_cities do
    # Cache all common combinations with these fallback cities
    [true, false]
    |> Enum.each(fn diverse ->
      [15, 10, 6]
      |> Enum.each(fn limit ->
        [50, 30]
        |> Enum.each(fn distance ->
          opts = [limit: limit, distance_threshold: distance, diverse_countries: diverse]
          cache_key = "popular_cities:#{inspect(opts)}"

          # Get fallback cities from central function
          cities = TriviaAdvisor.Locations.get_fallback_popular_cities(limit: limit)

          # Store in cache with 24hr TTL
          TriviaAdvisor.Cache.store(cache_key, cities, 86400)
        end)
      end)
    end)

    Logger.info("Stored fallback popular cities in cache")
  end
end

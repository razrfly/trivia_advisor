defmodule TriviaAdvisor.Locations.Oban.DailyRecalibrateWorker do
  @moduledoc """
  Oban worker that runs daily to update city coordinates based on venue locations.

  This worker automates the process previously handled by the mix cities.update_coordinates task.
  It calculates the average latitude and longitude of all venues in each city and
  updates the city record with those coordinates.

  Additionally, it precalculates and caches popular cities to prevent expensive
  computations during page loads.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{City, Venue}
  require Logger

  # Define a helper function to check environment
  defp debug_logging? do
    Application.get_env(:trivia_advisor, :env, :prod) in [:dev, :staging]
  end

  @impl Oban.Worker
  def perform(%{id: job_id} = _job) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting daily city coordinates update...")

    results =
      get_all_cities()
      |> Enum.map(&update_city_coordinates/1)

    # Calculate job statistics
    total_cities = length(results)
    updated = Enum.count(results, fn result -> match?({:ok, %{id: _}}, result) end)
    skipped = Enum.count(results, fn result -> match?({:ok, :no_update}, result) end)
    failed = Enum.count(results, fn result -> match?({:error, _}, result) end)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Format the log output as requested
    Logger.info("""
    Daily city coordinate update completed.
    Duration: #{duration_ms}ms
    Total cities processed: #{total_cities}
    Cities updated: #{updated}
    Cities skipped: #{skipped}
    Cities failed: #{failed}
    """)

    # Create metadata
    metadata = %{
      total_cities: total_cities,
      updated: updated,
      skipped: skipped,
      failed: failed,
      duration_ms: duration_ms
    }

    # Direct SQL update of the job's meta column
    Repo.update_all(
      from(j in "oban_jobs", where: j.id == ^job_id),
      set: [meta: metadata]
    )

    # After updating coordinates, precalculate and cache popular cities
    cache_popular_cities()

    :ok
  end

  # Get all cities from the database
  defp get_all_cities do
    Repo.all(City)
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
          # Cache each combination directly without scheduling a job
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

  # Update coordinates for a single city
  defp update_city_coordinates(%City{} = city) do
    if debug_logging?() do
      Logger.debug("Calculating coordinates for city: #{city.name}")
    end

    # Calculate average lat/lng from venues
    case calculate_avg_coordinates(city.id) do
      {lat, lng} when is_float(lat) and is_float(lng) ->
        # Update the city using update_all for better performance
        {updated_count, _} = Repo.update_all(
          from(c in City, where: c.id == ^city.id),
          set: [
            latitude: Decimal.from_float(lat),
            longitude: Decimal.from_float(lng),
            updated_at: DateTime.utc_now()
          ]
        )

        if updated_count > 0 do
          if debug_logging?() do
            Logger.debug("Updated #{city.name} coordinates: #{lat}, #{lng}")
          end
          {:ok, %{id: city.id, lat: lat, lng: lng}}
        else
          Logger.error("Failed to update #{city.name} coordinates: update operation returned 0 rows affected")
          {:error, :update_failed}
        end

      nil ->
        # Log skipped cities in dev/staging for debugging
        if debug_logging?() do
          Logger.debug("Skipped city: #{city.name} (no venue data)")
        end
        # No venues with coordinates found, return success but indicate no update
        {:ok, :no_update}
    end
  end

  # Calculate average coordinates from venues in a city
  defp calculate_avg_coordinates(city_id) do
    # Query to get average latitude and longitude
    query = from v in Venue,
            where: v.city_id == ^city_id and is_nil(v.latitude) == false and is_nil(v.longitude) == false,
            select: {
              fragment("AVG(CAST(? AS FLOAT))", v.latitude),
              fragment("AVG(CAST(? AS FLOAT))", v.longitude)
            }

    case Repo.one(query) do
      {lat, lng} when not is_nil(lat) and not is_nil(lng) ->
        {lat, lng}
      _ ->
        nil
    end
  end
end

defmodule TriviaAdvisor.Locations.Oban.DailyRecalibrateWorker do
  @moduledoc """
  Oban worker that runs daily to update city coordinates based on venue locations.

  This worker automates the process previously handled by the mix cities.update_coordinates task.
  It calculates the average latitude and longitude of all venues in each city and
  updates the city record with those coordinates.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{City, Venue}
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting daily city coordinates update")

    results =
      get_all_cities()
      |> Enum.map(&update_city_coordinates/1)

    # Count successful and failed updates
    successful = Enum.count(results, fn result -> match?({:ok, _}, result) end)
    failed = Enum.count(results, fn result -> match?({:error, _}, result) end)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    Logger.info("Completed daily city coordinates update in #{duration_ms}ms. " <>
                "Updated #{successful} cities successfully. Failed to update #{failed} cities.")

    :ok
  end

  # Get all cities from the database
  defp get_all_cities do
    Repo.all(City)
  end

  # Update coordinates for a single city
  defp update_city_coordinates(%City{} = city) do
    Logger.debug("Calculating coordinates for city: #{city.name}")

    # Calculate average lat/lng from venues
    case calculate_avg_coordinates(city.id) do
      {lat, lng} when is_float(lat) and is_float(lng) ->
        # Update the city
        city
        |> Ecto.Changeset.change(%{
          latitude: Decimal.from_float(lat),
          longitude: Decimal.from_float(lng)
        })
        |> Repo.update()
        |> case do
          {:ok, updated_city} ->
            Logger.debug("Updated #{city.name} coordinates: #{lat}, #{lng}")
            {:ok, updated_city}

          {:error, changeset} ->
            Logger.error("Failed to update #{city.name} coordinates: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      nil ->
        Logger.warning("No venues with coordinates found for #{city.name}")
        {:error, :no_venues}
    end
  end

  # Calculate average coordinates from venues in a city
  defp calculate_avg_coordinates(city_id) do
    # Query to get average latitude and longitude
    query = from v in Venue,
            where: v.city_id == ^city_id and not is_nil(v.latitude) and not is_nil(v.longitude),
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

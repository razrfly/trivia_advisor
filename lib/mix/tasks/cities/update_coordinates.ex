defmodule Mix.Tasks.Cities.UpdateCoordinates do
  @moduledoc """
  Mix task to calculate city coordinates by averaging venue coordinates.

  ## Examples

      # Update all cities
      mix cities.update_coordinates

      # Update a specific city by ID
      mix cities.update_coordinates --city-id=123

      # Update a specific city by slug
      mix cities.update_coordinates --city-slug=melbourne
  """

  use Mix.Task
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{City, Venue}
  require Logger

  @shortdoc "Calculate city coordinates based on venue locations"

  def run(args) do
    # Parse args
    {opts, _, _} = OptionParser.parse(args, strict: [
      city_id: :integer,
      city_slug: :string
    ])

    # Start the application
    Mix.Task.run("app.start")

    # Process cities based on options
    process_cities(opts)

    # Report success
    IO.puts("City coordinates updated successfully")
  end

  defp process_cities(opts) do
    city_id = Keyword.get(opts, :city_id)
    city_slug = Keyword.get(opts, :city_slug)

    cond do
      # Case 1: Specific city by ID
      city_id ->
        city = Repo.get(City, city_id)
        if city, do: update_city_coordinates(city)

      # Case 2: Specific city by slug
      city_slug ->
        city = Repo.get_by(City, slug: city_slug)
        if city, do: update_city_coordinates(city)

      # Case 3: All cities
      true ->
        Logger.info("Updating coordinates for all cities")
        Repo.all(City)
        |> Enum.each(&update_city_coordinates/1)
    end
  end

  defp update_city_coordinates(%City{} = city) do
    Logger.info("Calculating coordinates for city: #{city.name}")

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
            Logger.info("Updated #{city.name} coordinates: #{lat}, #{lng}")
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

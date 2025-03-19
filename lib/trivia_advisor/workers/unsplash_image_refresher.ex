defmodule TriviaAdvisor.Workers.UnsplashImageRefresher do
  @moduledoc """
  Oban worker that refreshes Unsplash images for countries and cities.

  Uses rate limiting to avoid hitting Unsplash API limits.
  """

  use Oban.Worker, queue: :images, max_attempts: 3
  require Logger
  alias TriviaAdvisor.Services.UnsplashService
  alias TriviaAdvisor.Repo
  import Ecto.Query

  # Delay between API requests in milliseconds (2 seconds by default)
  # Can be overridden at runtime by setting :persistent_term.put(:unsplash_request_delay, milliseconds)
  @request_delay 2000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type, "names" => names} = args} = _job) do
    country = Map.get(args, "country")

    if type == "city" && country do
      Logger.info("Starting Unsplash image refresh for #{length(names)} cities in #{country}")
    else
      Logger.info("Starting Unsplash image refresh for #{length(names)} #{type}s")
    end

    # Get configured delay, defaulting to @request_delay if not set
    delay =
      try do
        :persistent_term.get(:unsplash_request_delay)
      rescue
        _ -> @request_delay
      end

    # Process each item with a delay to avoid rate limiting
    names
    |> Enum.with_index()
    |> Enum.each(fn {name, index} ->
      # Add delay between requests (except for the first one)
      if index > 0 do
        Process.sleep(delay)
      end

      # Fetch the image based on the type
      try do
        case type do
          "country" ->
            Logger.info("Refreshing country image for #{name}")
            UnsplashService.get_country_image(name)
          "city" ->
            location_info = if country, do: "#{name} (#{country})", else: name
            Logger.info("Refreshing city image for #{location_info}")
            UnsplashService.get_city_image(name)
        end

        if type == "city" && country do
          Logger.info("Successfully refreshed #{type} image for #{name} in #{country}")
        else
          Logger.info("Successfully refreshed #{type} image for #{name}")
        end
      rescue
        e ->
          if type == "city" && country do
            Logger.error("Error refreshing #{type} image for #{name} in #{country}: #{inspect(e)}")
          else
            Logger.error("Error refreshing #{type} image for #{name}: #{inspect(e)}")
          end
      end
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => "refresh"}} = _job) do
    # This kicks off the daily refresh of all images
    Logger.info("Starting daily Unsplash image refresh")
    schedule_country_refresh()
    schedule_city_refresh()
    :ok
  end

  @doc """
  Schedule refresh of all country images.
  This should be called periodically (e.g., daily or weekly) to refresh the cache.
  """
  def schedule_country_refresh() do
    countries = fetch_all_country_names()

    Logger.info("Scheduling refresh for #{length(countries)} countries with venues")

    # Schedule a job to refresh country images with small batches
    countries
    |> Enum.chunk_every(10) # Process in batches of 10
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      # Stagger jobs by 30 minutes to avoid overlapping
      schedule_in = index * 30 * 60

      %{type: "country", names: batch}
      |> __MODULE__.new(schedule_in: schedule_in)
      |> Oban.insert()
    end)
  end

  @doc """
  Schedule refresh of all city images.
  This should be called periodically (e.g., daily or weekly) to refresh the cache.
  """
  def schedule_city_refresh() do
    cities_by_country = fetch_all_cities_with_country()

    total_cities = Enum.reduce(cities_by_country, 0, fn {_, cities}, acc -> acc + length(cities) end)
    Logger.info("Scheduling refresh for #{total_cities} cities with venues across #{map_size(cities_by_country)} countries")

    # Schedule jobs for each country's cities
    cities_by_country
    |> Enum.each(fn {country_name, cities} ->
      # Split large countries into batches of 10 if needed
      city_batches = Enum.chunk_every(cities, 10)

      Logger.info("Scheduling #{length(city_batches)} batch(es) for #{length(cities)} cities in #{country_name}")

      city_batches
      |> Enum.with_index()
      |> Enum.each(fn {batch, index} ->
        # Stagger jobs by 30 minutes within each country to avoid overlapping
        schedule_in = index * 30 * 60

        %{type: "city", names: batch, country: country_name}
        |> __MODULE__.new(schedule_in: schedule_in)
        |> Oban.insert()
      end)
    end)
  end

  @doc """
  Schedule a daily refresh job for all countries and cities.
  This creates a recurring job that will run daily at the specified time.
  """
  def schedule_daily_refresh do
    # Create a daily job that runs 24 hours from now (Oban doesn't support {hour, minute, second} format)
    Oban.insert!(
      %{action: "refresh"}
      |> __MODULE__.new(schedule_in: 86_400) # 24 hours in seconds
    )
  end

  @doc """
  Public version of fetch_all_cities_with_country for use in debug scripts.
  Returns cities grouped by country that have venues.
  """
  def fetch_all_cities_with_country_public do
    cities_by_country = fetch_all_cities_with_country()

    # Call fetch_all_city_names to make it used (for backward compatibility)
    _all_city_names = fetch_all_city_names()

    cities_by_country
  end

  # Private functions

  defp fetch_all_country_names do
    # Only return countries that have venues
    query = from c in TriviaAdvisor.Locations.Country,
      join: city in assoc(c, :cities),
      join: v in assoc(city, :venues),
      distinct: true,
      select: c.name

    Repo.all(query)
  end

  defp fetch_all_cities_with_country do
    # Query cities with their country that have venues
    query = from c in TriviaAdvisor.Locations.City,
      join: country in assoc(c, :country),
      join: v in assoc(c, :venues),
      distinct: true,
      select: {country.name, c.name}

    # Group cities by country
    Repo.all(query)
    |> Enum.group_by(
      fn {country_name, _} -> country_name end,
      fn {_, city_name} -> city_name end
    )
  end

  # Keep this function for backward compatibility
  defp fetch_all_city_names do
    fetch_all_cities_with_country()
    |> Enum.flat_map(fn {_, cities} -> cities end)
  end
end

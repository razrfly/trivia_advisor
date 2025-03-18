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
  def perform(%Oban.Job{args: %{"type" => type, "names" => names}} = _job) do
    Logger.info("Starting Unsplash image refresh for #{length(names)} #{type}s")

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
            Logger.info("Refreshing city image for #{name}")
            UnsplashService.get_city_image(name)
        end
        Logger.info("Successfully refreshed #{type} image for #{name}")
      rescue
        e -> Logger.error("Error refreshing #{type} image for #{name}: #{inspect(e)}")
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
    cities = fetch_all_city_names()

    Logger.info("Scheduling refresh for #{length(cities)} cities with venues")

    # Schedule a job to refresh city images with small batches
    cities
    |> Enum.chunk_every(10) # Process in batches of 10
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      # Stagger jobs by 30 minutes to avoid overlapping
      schedule_in = index * 30 * 60

      %{type: "city", names: batch}
      |> __MODULE__.new(schedule_in: schedule_in)
      |> Oban.insert()
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

  defp fetch_all_city_names do
    # Only return cities that have venues
    query = from c in TriviaAdvisor.Locations.City,
      join: v in assoc(c, :venues),
      distinct: true,
      select: c.name

    Repo.all(query)
  end
end

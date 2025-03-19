defmodule TriviaAdvisor.Workers.UnsplashImageRefresher do
  @moduledoc """
  Oban worker that refreshes Unsplash images for countries and cities.

  Uses rate limiting to avoid hitting Unsplash API limits.
  Stores image galleries in the database.
  """

  use Oban.Worker,
    queue: :images,
    max_attempts: 3,
    unique: [period: 60 * 60, fields: [:worker, :args], keys: [:unique_key]]
  require Logger
  alias TriviaAdvisor.Services.UnsplashImageFetcher
  alias TriviaAdvisor.Repo
  import Ecto.Query

  # Delay between API requests in milliseconds (2 seconds by default)
  # Can be overridden at runtime by setting :persistent_term.put(:unsplash_request_delay, milliseconds)
  @request_delay 10000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type, "names" => names} = args} = _job) do
    country = Map.get(args, "country")

    if type == "city" && country do
      Logger.info("Starting Unsplash image gallery refresh for #{length(names)} cities in #{country}")
    else
      Logger.info("Starting Unsplash image gallery refresh for #{length(names)} #{type}s")
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

      # Fetch and store images based on the type
      try do
        case type do
          "country" ->
            Logger.info("Refreshing country image gallery for #{name}")
            UnsplashImageFetcher.fetch_and_store_country_images(name)
          "city" ->
            location_info = if country, do: "#{name} (#{country})", else: name
            Logger.info("Refreshing city image gallery for #{location_info}")
            UnsplashImageFetcher.fetch_and_store_city_images(name, country)
        end

        if type == "city" && country do
          Logger.info("Successfully refreshed #{type} image gallery for #{name} in #{country}")
        else
          Logger.info("Successfully refreshed #{type} image gallery for #{name}")
        end
      rescue
        e ->
          if type == "city" && country do
            Logger.error("Error refreshing #{type} image gallery for #{name} in #{country}: #{inspect(e)}")
          else
            Logger.error("Error refreshing #{type} image gallery for #{name}: #{inspect(e)}")
          end
      end
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => "refresh"}} = _job) do
    # This kicks off the daily refresh of all images
    Logger.info("Starting daily Unsplash image gallery refresh")
    schedule_country_refresh()
    schedule_city_refresh()
    :ok
  end

  @doc """
  Schedule refresh of all country image galleries.
  This should be called periodically (e.g., daily or weekly) to refresh the galleries.
  """
  def schedule_country_refresh() do
    countries = fetch_all_country_names()

    Logger.info("Scheduling refresh for #{length(countries)} country galleries with venues")

    # Schedule a job to refresh country images with small batches
    batches = countries |> Enum.chunk_every(10) # Process in batches of 10

    # Log all batches to help debug
    Logger.debug("Country batches to be scheduled: #{inspect(batches)}")

    batches
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      # Stagger jobs by 30 minutes to avoid overlapping
      schedule_in = index * 30 * 60

      # Ensure we're not scheduling empty batches
      if Enum.empty?(batch) do
        Logger.warning("Skipping empty country batch at index #{index}")
      else
        # Create a unique key for this specific batch to prevent duplicates
        unique_batch_key = "country_batch_#{index}_#{Enum.join(batch, "_")}"

        args = %{
          type: "country",
          names: batch,
          unique_key: unique_batch_key  # Add unique key to args instead of using :id
        }

        case args
          |> __MODULE__.new(schedule_in: schedule_in)
          |> Oban.insert() do
          {:ok, job} ->
            Logger.info("Scheduled country batch job #{job.id} for #{inspect(batch)} in #{div(schedule_in, 60)} minutes")
          {:error, error} ->
            Logger.error("Failed to schedule country batch: #{inspect(error)}")
        end
      end
    end)
  end

  @doc """
  Schedule refresh of all city image galleries.
  This should be called periodically (e.g., daily or weekly) to refresh the galleries.
  """
  def schedule_city_refresh() do
    cities_by_country = fetch_all_cities_with_country()
    total_cities = cities_by_country |> Enum.map(fn {_, cities} -> length(cities) end) |> Enum.sum()
    country_count = map_size(cities_by_country)

    Logger.info("Scheduling Unsplash image refresh for #{total_cities} cities in #{country_count} countries")

    cities_by_country
    |> Enum.with_index()
    |> Enum.each(fn {{country, cities}, country_index} ->
      chunk_size = 10

      Logger.debug("Scheduling batches for #{length(cities)} cities in #{country}")

      cities
      |> Enum.chunk_every(chunk_size)
      |> Enum.with_index()
      |> Enum.each(fn {batch, batch_index} ->
        # Increase this delay from 30 minutes to 60 minutes
        # This gives more time between batches to avoid rate limiting
        schedule_in = country_index * 60 * 60 + batch_index * 10 * 60 # 60 min between countries, 10 min between batches

        # Skip empty batches
        if Enum.empty?(batch) do
          Logger.warning("Skipping empty city batch at index #{batch_index} for #{country}")
        else
          # Create a unique identifier for this job
          unique_batch_key = "city_batch_#{country}_#{batch_index}_#{Enum.join(batch, "_")}"

          args = %{
            "type" => "city",
            "names" => batch,
            "country" => country,
            "unique_key" => unique_batch_key
          }

          case args
            |> new(schedule_in: schedule_in)
            |> Oban.insert() do
            {:ok, job} ->
              Logger.info("Scheduled job #{job.id} to refresh #{length(batch)} cities in #{country} in #{div(schedule_in, 60)} minutes")
            {:error, error} ->
              Logger.error("Failed to schedule city batch for #{country}: #{inspect(error)}")
          end
        end
      end)
    end)
  end

  @doc """
  Schedule a daily refresh job for all countries and cities.
  This creates a recurring job that will run daily at the specified time.
  """
  def schedule_daily_refresh do
    # Create a job that runs daily at 1:00 AM UTC
    try do
      %{action: "refresh"}
      |> __MODULE__.new(schedule: "0 1 * * *")
      |> Oban.insert!()
      {:ok, :scheduled}
    rescue
      e ->
        Logger.error("Failed to schedule daily refresh: #{inspect(e)}")
        {:error, :scheduling_failed}
    end
  end

  @doc """
  Manually trigger a full refresh of all images.
  This will create a unique job to avoid duplicates.
  """
  def trigger_full_refresh do
    # Generate a unique timestamp to prevent duplicate jobs
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    unique_key = "full_refresh_#{timestamp}"

    Logger.info("Triggering full image refresh with unique key: #{unique_key}")

    args = %{
      action: "refresh",
      unique_key: unique_key  # Use uniqueness within the args
    }

    case args
      |> __MODULE__.new()
      |> Oban.insert() do
      {:ok, job} ->
        Logger.info("Scheduled full refresh job #{job.id}")
        {:ok, job.id}
      {:error, error} ->
        Logger.error("Failed to schedule full refresh: #{inspect(error)}")
        {:error, error}
    end
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

    countries = Repo.all(query)

    # Log the countries we're about to process
    Logger.info("Found #{length(countries)} countries: #{inspect(countries)}")

    # Ensure uniqueness by running through MapSet
    countries |> MapSet.new() |> MapSet.to_list()
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
  # credo:disable-for-next-line Credo.Check.Warning.UnusedPrivateFunction
  defp fetch_all_city_names do
    fetch_all_cities_with_country()
    |> Enum.flat_map(fn {_, cities} -> cities end)
  end
end

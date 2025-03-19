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

  # Refresh threshold configuration
  # These could be moved to application config if needed
  @country_high_venue_threshold 10
  @city_high_venue_threshold 5

  # Refresh interval configuration (in seconds)
  @daily_refresh 24 * 60 * 60  # 1 day
  @weekly_refresh 7 * 24 * 60 * 60  # 7 days
  @monthly_refresh 30 * 24 * 60 * 60  # 30 days

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "refresh"}}) do
    # This job is triggered daily and schedules individual refresh jobs
    schedule_country_refresh()
    schedule_city_refresh()

    # Schedule the next daily job
    schedule_daily_refresh()
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "country", "names" => names, "unique_key" => _unique_key}}) do
    Logger.info("Processing refresh job for #{length(names)} countries")

    for name <- names do
      country = Repo.get_by(TriviaAdvisor.Locations.Country, name: name)

      if country && needs_refresh?("country", country) do
        Logger.info("Fetching new images for country: #{name}")
        UnsplashImageFetcher.fetch_and_store_country_images(name)
      else
        if country do
          Logger.info("Skipping refresh for country: #{name} - not due for refresh yet")
        else
          Logger.warning("Country not found: #{name}")
        end
      end
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "city", "country" => country, "names" => city_names, "unique_key" => _unique_key}}) do
    Logger.info("Processing refresh job for #{length(city_names)} cities in #{country}")

    for city_name <- city_names do
      # Query all cities with the given name in the specified country
      cities =
        from(c in TriviaAdvisor.Locations.City,
          join: country_record in assoc(c, :country),
          where: c.name == ^city_name and country_record.name == ^country)
        |> Repo.all()

      case cities do
        [] ->
          Logger.warning("City not found: #{city_name} in #{country}")

        cities ->
          Enum.each(cities, fn city ->
            if needs_refresh?("city", city) do
              Logger.info("Fetching new images for city: #{city_name} (ID: #{city.id})")
              UnsplashImageFetcher.fetch_and_store_city_images(city_name)
            else
              Logger.info("Skipping refresh for city: #{city_name} (ID: #{city.id}) - not due for refresh yet")
            end
          end)
      end
    end

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

  # Check if a location needs to be refreshed based on venue count and last refresh time
  defp needs_refresh?(type, record) do
    # Get venue count
    venue_count = case type do
      "country" -> get_country_venue_count(record.id)
      "city" -> get_city_venue_count(record.id)
    end

    # Determine refresh interval based on type and venue count
    refresh_interval = determine_refresh_interval(type, venue_count)

    # Check last refresh time (if it exists)
    gallery = record.unsplash_gallery

    cond do
      # If no gallery exists yet, it definitely needs a refresh
      is_nil(gallery) -> true

      # If last_refreshed_at is missing, it needs a refresh
      !Map.has_key?(gallery, "last_refreshed_at") -> true

      # Otherwise check if enough time has passed since last refresh
      true ->
        last_refreshed_at =
          gallery["last_refreshed_at"]
          |> DateTime.from_iso8601()
          |> case do
               {:ok, datetime, _} -> datetime
               _ -> DateTime.add(DateTime.utc_now(), -refresh_interval - 1, :second)
             end

        seconds_since_refresh = DateTime.diff(DateTime.utc_now(), last_refreshed_at)
        seconds_since_refresh >= refresh_interval
    end
  end

  # Determine refresh interval based on location type and venue count
  defp determine_refresh_interval(type, venue_count) do
    case type do
      "country" when venue_count >= @country_high_venue_threshold ->
        @daily_refresh
      "city" when venue_count >= @city_high_venue_threshold ->
        @weekly_refresh
      _ ->
        @monthly_refresh
    end
  end

  # Helper to get venue count for a country
  defp get_country_venue_count(country_id) do
    # Using string-based query since TriviaAdvisor.Venues.Venue is not available
    query = """
    SELECT COUNT(v.id)
    FROM venues v
    JOIN cities c ON v.city_id = c.id
    WHERE c.country_id = $1
    """

    %{rows: [[count]]} = Repo.query!(query, [country_id])
    count || 0
  end

  # Helper to get venue count for a city
  defp get_city_venue_count(city_id) do
    # Using string-based query since TriviaAdvisor.Venues.Venue is not available
    query = """
    SELECT COUNT(v.id)
    FROM venues v
    WHERE v.city_id = $1
    """

    %{rows: [[count]]} = Repo.query!(query, [city_id])
    count || 0
  end
end

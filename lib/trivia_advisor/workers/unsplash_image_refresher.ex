defmodule TriviaAdvisor.Workers.UnsplashImageRefresher do
  @moduledoc """
  Oban worker that refreshes Unsplash images for countries and cities.

  Optimized for Unsplash's production rate limit of 5,000 requests per hour.
  Stores image galleries in the database.
  """

  use Oban.Worker,
    queue: :images,
    max_attempts: 3,
    unique: [period: 60 * 60, fields: [:worker, :args], keys: [:unique_key]]
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Services.UnsplashImageFetcher
  import Ecto.Query

  # Refresh threshold configuration
  # These could be moved to application config if needed
  @country_high_venue_threshold 10
  @city_high_venue_threshold 5

  # Refresh interval configuration (in seconds)
  @daily_refresh 7 * 24 * 60 * 60  # 7 days instead of 1 day
  @weekly_refresh 14 * 24 * 60 * 60  # 14 days instead of 7 days
  @monthly_refresh 60 * 24 * 60 * 60  # 60 days instead of 30 days

  # Rate limit configuration
  @production_rate_limit 5000  # Requests per hour in production
  @req_buffer_percent 0.8      # Use 80% of allowed requests to be safe
  @requests_per_location 1     # Each location typically uses 1 API request

  # Batch sizing
  @max_countries_per_batch 27  # Process all countries in one batch (we have 27 total)
  @max_cities_per_batch 200    # Process cities in larger batches (we have ~1455 total)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "refresh"}}) do
    # This job is triggered weekly and schedules consolidated refresh jobs
    schedule_country_refresh()
    schedule_city_refresh()

    # Schedule the next weekly job
    schedule_weekly_refresh()
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "country", "names" => names, "unique_key" => _unique_key}}) do
    Logger.info("Processing refresh job for #{length(names)} countries")

    # Process all countries with rate limiting
    process_locations_with_rate_limiting("country", names)

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "city", "batch_index" => batch_index, "names" => city_names, "unique_key" => _unique_key}}) do
    Logger.info("Processing refresh job for batch #{batch_index} with #{length(city_names)} cities")

    # Process cities with rate limiting
    process_locations_with_rate_limiting("city", city_names)

    :ok
  end

  # Process locations with built-in rate limiting
  defp process_locations_with_rate_limiting(type, names) do
    # Calculate a reasonable pause between API calls to stay within rate limits
    # Using 5000 requests/hour = ~1.4 requests/second, so we'll aim for ~1 request/second
    pause_ms = 1000

    # Process each location with a pause between to avoid rate limiting
    for name <- names do
      case type do
        "country" ->
          country = get_country_by_name(name)
          if country && needs_refresh?("country", country) do
            Logger.info("Fetching new images for country: #{name}")
            UnsplashImageFetcher.fetch_and_store_country_images(name)
            # Pause to respect rate limits
            Process.sleep(pause_ms)
          else
            if country do
              Logger.info("Skipping refresh for country: #{name} - not due for refresh yet")
            else
              Logger.warning("Country not found: #{name}")
            end
          end

        "city" ->
          # Query all cities with the given name
          cities =
            from(c in TriviaAdvisor.Locations.City,
              where: c.name == ^name)
            |> Repo.all()

          case cities do
            [] ->
              Logger.warning("City not found: #{name}")

            cities ->
              Enum.each(cities, fn city ->
                if needs_refresh?("city", city) do
                  Logger.info("Fetching new images for city: #{name} (ID: #{city.id})")
                  UnsplashImageFetcher.fetch_and_store_city_images(name)
                  # Pause to respect rate limits
                  Process.sleep(pause_ms)
                else
                  Logger.info("Skipping refresh for city: #{name} (ID: #{city.id}) - not due for refresh yet")
                end
              end)
          end
      end
    end
  end

  @doc """
  Schedule refresh of all country image galleries.
  Since we have a high request limit (5000/hour), we can process all countries in one job.
  """
  def schedule_country_refresh() do
    countries = fetch_all_country_names()
    countries_count = length(countries)

    Logger.info("Scheduling consolidated refresh for #{countries_count} country galleries")

    # Create a unique key for this batch
    unique_key = "country_consolidated_#{DateTime.utc_now() |> Calendar.strftime("%Y%m%d")}"

    args = %{
      type: "country",
      names: countries,
      unique_key: unique_key
    }

    case args
      |> __MODULE__.new()
      |> Oban.insert() do
      {:ok, job} ->
        Logger.info("Scheduled consolidated country refresh job #{job.id} for #{countries_count} countries")
      {:error, error} ->
        Logger.error("Failed to schedule country refresh: #{inspect(error)}")
    end
  end

  @doc """
  Schedule refresh of all city image galleries.
  With the 5000/hour rate limit, we can use significantly larger batches.
  """
  def schedule_city_refresh() do
    all_cities = fetch_all_city_names()
    cities_count = length(all_cities)

    Logger.info("Scheduling consolidated refresh for #{cities_count} cities")

    # Process in larger batches of up to @max_cities_per_batch cities
    all_cities
    |> Enum.chunk_every(@max_cities_per_batch)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      # Add a 1-hour delay between batches to ensure we stay within rate limits
      schedule_in = index * 60 * 60

      # Create a unique key for this batch
      unique_key = "city_batch_#{index}_#{DateTime.utc_now() |> Calendar.strftime("%Y%m%d")}"

      args = %{
        "type" => "city",
        "batch_index" => index,
        "names" => batch,
        "unique_key" => unique_key
      }

      case args
        |> new(schedule_in: schedule_in)
        |> Oban.insert() do
        {:ok, job} ->
          Logger.info("Scheduled job #{job.id} to refresh batch #{index} with #{length(batch)} cities in #{div(schedule_in, 60)} minutes")
        {:error, error} ->
          Logger.error("Failed to schedule city batch #{index}: #{inspect(error)}")
      end
    end)
  end

  @doc """
  Schedule a weekly refresh job for all countries and cities.
  This creates a recurring job that will run weekly at the specified time.
  """
  def schedule_weekly_refresh do
    # Create a job that runs weekly at 1:00 AM UTC on Monday
    try do
      %{action: "refresh"}
      |> __MODULE__.new(schedule: "0 1 * * 1")  # Weekly on Monday at 1 AM
      |> Oban.insert!()
      {:ok, :scheduled}
    rescue
      e ->
        Logger.error("Failed to schedule weekly refresh: #{inspect(e)}")
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
      unique_key: unique_key
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
    fetch_all_cities_with_country()
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

  # Return all unique city names (not grouped by country)
  defp fetch_all_city_names do
    query = from c in TriviaAdvisor.Locations.City,
      join: v in assoc(c, :venues),
      distinct: true,
      select: c.name

    Repo.all(query)
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

  # Helper to get a country by name
  defp get_country_by_name(name) do
    Repo.get_by(TriviaAdvisor.Locations.Country, name: name)
  end
end

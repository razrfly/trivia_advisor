defmodule TriviaAdvisor.Scraping.Oban.InquizitionIndexJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Events.{Event, EventSource}
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob
  alias TriviaAdvisor.Scraping.RateLimiter

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting Inquizition Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Get the Inquizition source
    source = Repo.get_by!(Source, name: "inquizition")

    # Call the existing scraper function with error handling
    case try_scrape() do
      {:ok, results} ->
        # Count total venues found
        total_venues = length(results)
        Logger.info("📊 Found #{total_venues} total venues from Inquizition")

        # Load existing event sources for comparison (for venue skipping)
        existing_sources_by_venue = load_existing_sources(source.id)

        # Limit venues if needed (for testing)
        venues_to_process = if limit, do: Enum.take(results, limit), else: results
        limited_count = length(venues_to_process)

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{total_venues} total)")
        end

        # Filter venues based on last seen time - only process new venues or those not seen recently
        venues_to_enqueue = venues_to_process
        |> Enum.filter(fn [ok: venue] ->
          should_process_venue?(venue, existing_sources_by_venue)
        end)

        # Count the number of venues that will be processed vs skipped
        to_process_count = length(venues_to_enqueue)
        skipped_count = limited_count - to_process_count

        Logger.info("📊 Processing #{to_process_count} venues, skipping #{skipped_count} unchanged venues")

        # Use the RateLimiter to schedule detail jobs with delay
        enqueued_count = RateLimiter.schedule_jobs_with_delay(
          venues_to_enqueue,
          fn venue_data, _index, scheduled_in ->
            # Extract venue from the ok tuple
            [ok: venue] = venue_data

            # Special case for The White Horse which has known time data
            time_text = cond do
              venue.name == "The White Horse" && (is_nil(Map.get(venue, :time_text)) || Map.get(venue, :time_text) == "") ->
                "Sundays, 7pm"
              true ->
                Map.get(venue, :time_text) || ""
            end

            # Extract day_of_week and start_time from time_text if not already present
            {day_of_week, start_time} = cond do
              venue.name == "The White Horse" && (is_nil(Map.get(venue, :day_of_week)) || is_nil(Map.get(venue, :start_time))) ->
                {7, "19:00"}  # Sunday at 7pm
              true ->
                {
                  Map.get(venue, :day_of_week) || extract_day_of_week(%{time_text: time_text}),
                  Map.get(venue, :start_time) || extract_start_time(%{time_text: time_text})
                }
            end

            # Build venue data for the detail job - Include BOTH name AND address for venue identification
            venue_data = %{
              "name" => venue.name,
              "address" => venue.address,
              "phone" => venue.phone,
              "website" => venue.website,
              "source_id" => source.id,
              "time_text" => time_text,
              "day_of_week" => day_of_week,
              "start_time" => start_time,
              "frequency" => Map.get(venue, :frequency) || "weekly",
              "entry_fee" => Map.get(venue, :entry_fee) || "2.50",
              "description" => Map.get(venue, :description),
              "hero_image" => Map.get(venue, :hero_image),
              "hero_image_url" => Map.get(venue, :hero_image_url),
              "facebook" => Map.get(venue, :facebook),
              "instagram" => Map.get(venue, :instagram),
              "source_url" => generate_source_url(venue)
            }

            # Create the job with the scheduled_in parameter
            %{venue_data: venue_data}
            |> InquizitionDetailJob.new(schedule_in: scheduled_in)
          end
        )

        Logger.info("📥 Enqueued #{enqueued_count} Inquizition detail jobs with rate limiting")

        # Create metadata for reporting
        metadata = %{
          "total_venues" => total_venues,
          "limited_to" => limited_count,
          "enqueued_jobs" => enqueued_count,
          "skipped_venues" => skipped_count,
          "applied_limit" => limit,
          "source_id" => source.id,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Direct SQL update of the job's meta column
        Repo.update_all(
          from(j in "oban_jobs", where: j.id == ^job_id),
          set: [meta: metadata]
        )

        {:ok, %{
          venue_count: total_venues,
          enqueued_jobs: enqueued_count,
          skipped_venues: skipped_count
        }}

      {:error, reason} ->
        # Handle the error case
        Logger.error("❌ Failed to scrape Inquizition venues: #{inspect(reason)}")

        # Update job metadata with error
        error_metadata = %{
          "error" => inspect(reason),
          "error_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Direct SQL update of the job's meta column
        Repo.update_all(
          from(j in "oban_jobs", where: j.id == ^job_id),
          set: [meta: error_metadata]
        )

        # Return the error
        {:error, reason}
    end
  end

  # Create a consistent source URL - we don't have real URLs so create them from venue details
  defp generate_source_url(venue) do
    base_url = "https://inquizition.com/find-a-quiz/"
    slug = venue.name
           |> String.downcase()
           |> String.replace(~r/[^a-z0-9]+/, "-")
           |> String.trim("-")

    "#{base_url}##{slug}"
  end

  # Load existing event sources for comparison, keyed by normalized venue name + address
  defp load_existing_sources(source_id) do
    # Find all EventSources for this source
    query = from es in EventSource,
      join: e in Event, on: es.event_id == e.id,
      join: v in Venue, on: e.venue_id == v.id,
      where: es.source_id == ^source_id,
      select: {
        v.name,
        v.address,
        es.last_seen_at
      }

    # Group by name + address
    Repo.all(query)
    |> Enum.reduce(%{}, fn {name, address, last_seen_at}, acc ->
      key = generate_venue_key(name, address)
      Map.put(acc, key, last_seen_at)
    end)
  end

  # Check if we should process this venue
  defp should_process_venue?(venue, existing_sources_by_venue) do
    # Generate venue key for lookup
    venue_key = generate_venue_key(venue.name, venue.address)

    # Get the last time this venue was seen (if ever)
    last_seen_at = Map.get(existing_sources_by_venue, venue_key)

    if last_seen_at do
      # Venue exists - check if it was processed recently
      days_ago = RateLimiter.skip_if_updated_within_days()
      cutoff_date = DateTime.add(DateTime.utc_now(), -days_ago * 24 * 60 * 60, :second)

      # Only process if last_seen_at is older than the cutoff date
      case DateTime.compare(last_seen_at, cutoff_date) do
        :lt ->
          # Venue was last seen before cutoff date - should process
          Logger.info("🔄 Processing venue '#{venue.name}' - last seen #{DateTime.to_iso8601(last_seen_at)}")
          true
        _ ->
          # Venue was seen recently - skip
          Logger.info("⏩ Skipping venue '#{venue.name}' - recently seen on #{DateTime.to_iso8601(last_seen_at)}")
          false
      end
    else
      # Venue has never been seen - should process
      Logger.info("🆕 Processing new venue '#{venue.name}'")
      true
    end
  end

  # Generate a consistent key for venue lookup based on name + address
  defp generate_venue_key(name, address) do
    normalized_name = name
                      |> String.downcase()
                      |> String.trim()

    normalized_address = address
                         |> String.downcase()
                         |> String.replace(~r/\s+/, " ")
                         |> String.trim()

    "#{normalized_name}|#{normalized_address}"
  end

  # Wrap the scraper call in a try/rescue to handle any errors
  defp try_scrape do
    try do
      results = Scraper.scrape()
      {:ok, results}
    rescue
      e ->
        Logger.error("❌ Error in Inquizition scraper: #{inspect(e)}")
        {:error, "Scraper error: #{Exception.message(e)}"}
    catch
      kind, reason ->
        Logger.error("❌ Caught #{kind} in Inquizition scraper: #{inspect(reason)}")
        {:error, "Caught #{kind}: #{inspect(reason)}"}
    end
  end

  # Extract day of week from venue data, with fallback to parsing time_text
  defp extract_day_of_week(venue) do
    case Map.get(venue, :day_of_week) do
      nil ->
        # Try to parse from time_text
        time_text = Map.get(venue, :time_text) || ""
        case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time_text(time_text) do
          {:ok, %{day_of_week: day}} -> day
          _ -> nil
        end
      day -> day
    end
  end

  # Extract start time from venue data, with fallback to parsing time_text
  defp extract_start_time(venue) do
    case Map.get(venue, :start_time) do
      nil ->
        # Try to parse from time_text
        time_text = Map.get(venue, :time_text) || ""
        case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time_text(time_text) do
          {:ok, %{start_time: time}} -> time
          _ -> nil
        end
      time -> time
    end
  end
end

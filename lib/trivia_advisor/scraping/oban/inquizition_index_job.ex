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

    # First, pre-fetch all existing event sources for comparison
    # This lets us determine which venues to skip before any expensive processing
    existing_sources_by_venue = load_existing_sources(source.id)

    # Call the scraper to get all raw venue data (without processing)
    case try_fetch_venues() do
      {:ok, raw_venues} ->
        # Count total venues found
        total_venues = length(raw_venues)
        Logger.info("📊 Found #{total_venues} total raw venues")

        # Limit venues if needed (for testing)
        venues_to_process = if limit, do: Enum.take(raw_venues, limit), else: raw_venues
        limited_count = length(venues_to_process)

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{total_venues} total)")
        end

        # Pre-filter venues that should be skipped based on last_seen_at
        # This is the key improvement - we filter BEFORE expensive operations
        {to_process, to_skip} = venues_to_process
                                |> Enum.split_with(fn venue_data ->
                                  should_process_venue?(venue_data, existing_sources_by_venue)
                                end)

        processed_count = length(to_process)
        skipped_count = length(to_skip)

        Logger.info("🧮 After filtering: Processing #{processed_count} venues, skipping #{skipped_count} venues")

        # Log which venues are being skipped
        Enum.each(to_skip, fn venue_data ->
          venue_key = generate_venue_key(venue_data["name"], venue_data["address"])
          last_seen_at = Map.get(existing_sources_by_venue, venue_key)

          if last_seen_at do
            Logger.info("⏩ Skipping venue '#{venue_data["name"]}' - recently seen on #{DateTime.to_iso8601(last_seen_at)}")
          end
        end)

        # Now process only the venues that need processing
        processed_venues = if processed_count > 0 do
          Logger.info("🔄 Processing #{processed_count} venues that need updating")

          # Process the venues through the scraper
          process_results = process_venues(to_process, source.id)

          # Log the results for debugging
          Logger.info("📊 Processing results: #{inspect(process_results)}")

          # Filter only successful results
          filtered_results = Enum.filter(process_results, fn
            [ok: _venue] -> true  # Match the [ok: venue] format directly
            _ -> false
          end)

          Logger.info("📊 Filtered venues for enqueueing: #{inspect(filtered_results)}")

          filtered_results
        else
          []
        end

        # Use the RateLimiter to schedule detail jobs with delay
        Logger.info("🔄 Scheduling jobs for #{length(processed_venues)} venues...")
        enqueued_count = RateLimiter.schedule_jobs_with_delay(
          processed_venues,
          fn [ok: venue], _index, scheduled_in ->  # Match [ok: venue] format directly
            # Extract time_text from venue or use empty string as default
            time_text = Map.get(venue, :time_text) || ""

            # Extract day_of_week and start_time from venue or time_text
            {day_of_week, start_time} = {
              Map.get(venue, :day_of_week) || extract_day_of_week(%{time_text: time_text}),
              Map.get(venue, :start_time) || extract_start_time(%{time_text: time_text})
            }

            # Build venue data for the detail job
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
        Logger.error("❌ Failed to fetch Inquizition venues: #{inspect(reason)}")

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

  # Check if we should process this venue (now works with raw venue data)
  defp should_process_venue?(venue_data, existing_sources_by_venue) do
    # Get name and address from the venue data
    name = venue_data["name"]
    address = venue_data["address"]

    # Generate venue key for lookup
    venue_key = generate_venue_key(name, address)

    # Get the last time this venue was seen (if ever)
    last_seen_at = Map.get(existing_sources_by_venue, venue_key)

    if last_seen_at do
      # Venue exists - check if it was processed recently
      days_ago = RateLimiter.skip_if_updated_within_days()
      Logger.debug("🔍 Skip threshold is #{days_ago} days - venue '#{name}'")

      cutoff_date = DateTime.add(DateTime.utc_now(), -days_ago * 24 * 60 * 60, :second)

      # Only process if last_seen_at is older than the cutoff date
      case DateTime.compare(last_seen_at, cutoff_date) do
        :lt ->
          # Venue was last seen before cutoff date - should process
          Logger.info("🔄 Will process venue '#{name}' - last seen #{DateTime.to_iso8601(last_seen_at)}")
          true
        _ ->
          # Venue was seen recently - skip
          Logger.info("⏩ Will skip venue '#{name}' - recently seen on #{DateTime.to_iso8601(last_seen_at)}")
          false
      end
    else
      # Venue has never been seen - should process
      Logger.info("🆕 Will process new venue '#{name}'")
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

  # Just fetch the venues without processing them
  defp try_fetch_venues do
    try do
      # Call the scraper to get the raw venue data (without processing)
      raw_venues = Scraper.fetch_raw_venues()
      {:ok, raw_venues}
    rescue
      e ->
        Logger.error("❌ Error fetching Inquizition venues: #{inspect(e)}")
        {:error, "Fetch error: #{Exception.message(e)}"}
    catch
      kind, reason ->
        Logger.error("❌ Caught #{kind} fetching Inquizition venues: #{inspect(reason)}")
        {:error, "Caught #{kind}: #{inspect(reason)}"}
    end
  end

  # Process a list of venues that need updating
  defp process_venues(venues_to_process, source_id) do
    Enum.map(venues_to_process, fn venue_data ->
      try do
        # First try to find existing venue directly in the database without triggering any Google lookups
        venue_name = venue_data["name"]
        venue_address = venue_data["address"]

        case find_venue_by_name_and_address(venue_name, venue_address) do
          %{id: id} = _venue when not is_nil(id) ->
            # Found exact venue - use it directly without calling process_venue
            Logger.info("✅ Using existing venue directly: #{venue_name}")
            # Return nil instead of [ok: venue] so this won't be scheduled for detail processing
            Logger.info("⏩ Skipping detail job for existing venue: #{venue_name}")
            nil

          nil ->
            # No exact match found - have to use full processing
            # Process each venue that needs updating through the scraper
            Logger.info("🔄 Processing venue with scraper: #{venue_name}")
            result = Scraper.process_single_venue(venue_data, source_id)

            # Extract the venue from the result format
            case result do
              [ok: venue] ->
                # Return the processed venue in the expected format for detail job scheduling
                Logger.info("✅ Successfully processed venue: #{venue_data["name"]}")
                [ok: venue]
              _ ->
                Logger.error("❌ Failed to process venue: #{venue_data["name"]}")
                nil
            end
        end
      rescue
        e ->
          Logger.error("❌ Error processing venue #{venue_data["name"]}: #{inspect(e)}")
          {:error, "Processing error: #{Exception.message(e)}"}
      catch
        kind, reason ->
          Logger.error("❌ Caught #{kind} processing venue #{venue_data["name"]}: #{inspect(reason)}")
          {:error, "Caught #{kind}: #{inspect(reason)}"}
      end
    end)
    |> Enum.filter(fn result -> result != nil end)  # Filter out nil results
  end

  # Helper to find venue by name and address directly in the database
  defp find_venue_by_name_and_address(name, address) when is_binary(name) and is_binary(address) do
    Repo.one(from v in TriviaAdvisor.Locations.Venue,
      where: v.name == ^name and v.address == ^address,
      limit: 1)
  end
  defp find_venue_by_name_and_address(_, _), do: nil

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

  @doc """
  Create a test run for a single venue to verify processing works.
  Used for testing only.
  """
  def test_single_venue(venue_name, venue_address) do
    # Find the venue in the database first, to make sure it exists
    venue_data = %{
      "name" => venue_name,
      "address" => venue_address,
      "time_text" => "",
      "phone" => nil,
      "website" => nil
    }

    # Get the Inquizition source
    source = Repo.get_by!(Source, name: "inquizition")

    Logger.info("🧪 Testing single venue processing for: #{venue_name}, #{venue_address}")

    # Process the single venue
    result = Scraper.process_single_venue(venue_data, source.id)

    # Return the result
    case result do
      [ok: venue] ->
        Logger.info("✅ Successfully processed test venue: #{venue.name}")
        {:ok, venue}
      nil ->
        Logger.error("❌ Failed to process test venue: #{venue_name}")
        {:error, :processing_failed}
      other ->
        Logger.error("❌ Unexpected result: #{inspect(other)}")
        {:error, :unexpected_result}
    end
  end
end

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
    Logger.debug("📊 Found source: #{inspect(source)}")

    # First, pre-fetch all existing event sources for comparison
    # This lets us determine which venues to skip before any expensive processing
    existing_sources_by_venue = load_existing_sources(source.id)
    Logger.debug("📊 Loaded #{map_size(existing_sources_by_venue)} existing sources")

    # Call the scraper to get all raw venue data (without processing)
    case try_fetch_venues() do
      {:ok, raw_venues} ->
    # Count total venues found
        total_venues = length(raw_venues)
        Logger.info("📊 Found #{total_venues} total raw venues")
        Logger.debug("📊 Raw venues: #{inspect(raw_venues)}")

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
        Logger.debug("📊 Venues to process: #{inspect(to_process)}")

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

        # Log each venue being scheduled
        Enum.each(processed_venues, fn [ok: %{venue: venue}] ->
          Logger.debug("🔄 Will schedule detail job for: #{venue.name}")
        end)

        Logger.debug("🔄 Calling RateLimiter.schedule_jobs_with_delay with #{length(processed_venues)} venues")

        enqueued_count = RateLimiter.schedule_jobs_with_delay(
          processed_venues,
          fn [ok: %{venue: venue, extra_data: extra_data}], index, scheduled_in ->
            # Extract time_text from extra_data
            time_text = Map.get(extra_data, :time_text) || ""
            Logger.debug("🔄 Building venue data for job #{index} - #{venue.name}")

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

            Logger.debug("🔄 Created venue_data for job: #{inspect(venue_data)}")

        # Create the job with the scheduled_in parameter
            job = %{venue_data: venue_data}
        |> InquizitionDetailJob.new(schedule_in: scheduled_in)

            Logger.debug("🔄 Created job for venue #{venue.name} to run in #{scheduled_in} seconds")

            # Add extra debugging to see the job structure
            Logger.debug("🔄 Job structure: #{inspect(job)}")

            job
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
    # Find all EventSources for this source - this captures venues that have been fully processed
    event_sources = from(es in EventSource,
      join: e in Event, on: es.event_id == e.id,
      join: v in Venue, on: e.venue_id == v.id,
      where: es.source_id == ^source_id,
      select: {
        v.name,
        v.address,
        es.last_seen_at
      })
      |> Repo.all()
      |> Enum.reduce(%{}, fn {name, address, last_seen_at}, acc ->
        key = generate_venue_key(name, address)
        Map.put(acc, key, last_seen_at)
      end)

    # Also find all existing venues in the database, even if they don't have events yet
    # This prevents re-processing venues that exist but don't yet have events
    existing_venues = from(v in Venue,
      where: not is_nil(v.postcode), # Focus on venues with postcodes
      select: {v.name, v.address})
      |> Repo.all()
      |> Enum.reduce(event_sources, fn {name, address}, acc ->
        key = generate_venue_key(name, address)
        # If this venue doesn't have an event source record yet, add it with a recent timestamp
        # to prevent it from being processed again
        if not Map.has_key?(acc, key) do
          Map.put(acc, key, DateTime.utc_now())
        else
          acc
        end
      end)

    existing_venues
  end

  # Check if a venue should be processed based on its last seen date
  defp should_process_venue?(venue, existing_sources_by_venue) do
    venue_name = venue["name"]
    venue_address = venue["address"]

    # Add extra debugging for all venues, not just problematic ones
    Logger.debug("🧪 Checking venue: #{venue_name} at #{venue_address}")

    # Extract postcode for direct DB lookup
    postcode = case Regex.run(~r/[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}/i, venue_address) do
      [matched_postcode] -> String.trim(matched_postcode)
      nil -> nil
    end

    # If we find a venue with this postcode, immediately skip it
    if postcode && Repo.exists?(from v in Venue, where: v.postcode == ^postcode) do
      Logger.info("⏩ Skipping venue - postcode #{postcode} already exists in database: #{venue_name}")
      false
    else
      # No postcode match, so try comprehensive DB lookup
      existing_venue = find_venue_by_name_and_address(venue_name, venue_address)

      # If it exists, we should skip it
      if existing_venue do
        Logger.info("⏩ Skipping venue - already exists in database: #{venue_name} (ID: #{existing_venue.id})")
        false
      else
        # If not found in database, proceed with regular check based on last_seen_at
        venue_key = generate_venue_key(venue_name, venue_address)

        # Add extra logging for problematic venues we're tracking
        problematic_venues = ["The White Horse", "The Mitre", "The Railway", "The Bull"]
        is_problematic = venue_name in problematic_venues or Enum.any?(problematic_venues, fn prefix ->
          String.starts_with?(venue_name, prefix)
        end)

        if is_problematic do
          Logger.debug("🔍 Checking problematic venue: #{venue_name} at #{venue_address}")
          Logger.debug("🔑 Venue key: #{venue_key}")
          Logger.debug("🗂️ Keys in existing_sources_by_venue: #{inspect(Map.keys(existing_sources_by_venue) |> Enum.filter(fn k -> String.contains?(k, String.downcase(venue_name)) end))}")
        end

        # Get the last_seen_at timestamp for this venue (if it exists)
        last_seen_at = Map.get(existing_sources_by_venue, venue_key)

        cond do
          # One final desperate check for problematic venues - search by name
          is_nil(last_seen_at) && is_problematic &&
          (Repo.exists?(from v in Venue, where: v.name == ^venue_name) ||
           Repo.exists?(from v in Venue, where: fragment("LOWER(?) LIKE LOWER(?)", v.name, ^"%#{venue_name}%"))) ->
            Logger.info("⏩ Emergency skip - name match found in database: #{venue_name}")
            false

          # Venue not seen before, should process
          is_nil(last_seen_at) ->
            Logger.info("🆕 New venue not seen before: #{venue_name}")
            true

          # Check if we've seen it recently
          true ->
            # Calculate cutoff date (5 days ago)
            cutoff_date = DateTime.utc_now() |> DateTime.add(-1 * 24 * 60 * 60 * RateLimiter.skip_if_updated_within_days(), :second)

            # Compare last_seen_at with cutoff date
            case DateTime.compare(last_seen_at, cutoff_date) do
              :lt ->
                # Last seen before cutoff date, should process
                Logger.info("🔄 Venue seen before cutoff date, will process: #{venue_name}")
                true
              _ ->
                # Last seen after cutoff date, should skip
                Logger.info("⏩ Skipping venue - recently seen: #{venue_name} on #{DateTime.to_iso8601(last_seen_at)}")
                false
            end
        end
      end
    end
  end

  # Generate a consistent key for venue lookup based on name + address
  defp generate_venue_key(name, address) do
    # Remove any parenthetical suffixes from venue names (e.g. "The Railway (address)" -> "The Railway")
    name_without_suffix = name
                      |> String.replace(~r/\s*\([^)]+\)\s*$/, "")
                      |> String.trim()

    normalized_name = name_without_suffix
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
  defp process_venues(venues_to_process, _source_id) do
    Logger.info("📊 Starting process_venues with #{length(venues_to_process)} venues to process")
    Logger.debug("📊 Venues to process details: #{inspect(venues_to_process)}")

    # We don't need the source in this function currently

    results = Enum.map(venues_to_process, fn venue_data ->
      try do
        # First try to find existing venue directly in the database without triggering any Google lookups
        venue_name = venue_data["name"]
        venue_address = venue_data["address"]
        time_text = venue_data["time_text"] || ""
        phone = venue_data["phone"]
        website = venue_data["website"]

        Logger.info("🔍 Looking up venue '#{venue_name}' in the database")
        Logger.debug("🔍 Full venue data: #{inspect(venue_data)}")

        case find_venue_by_name_and_address(venue_name, venue_address) do
          %{id: id} = existing_venue when not is_nil(id) ->
            # Found exact venue - use it directly without calling process_venue
            Logger.info("✅ Using existing venue directly: #{venue_name}")
            Logger.debug("✅ Existing venue details: #{inspect(existing_venue)}")
            # Return the venue and additional data to schedule a detail job for updating
            [ok: %{venue: existing_venue, extra_data: %{time_text: time_text}}]

          nil ->
            # No exact match found - just prepare data for the detail job to process
            # We don't want to do Google lookups here in the index job
            Logger.info("🆕 Preparing new venue for detail job: #{venue_name}")

            # Create a bare venue struct with just the basic info
            venue = %Venue{
              name: venue_name,
              address: venue_address,
              phone: phone,
              website: website
            }

            Logger.debug("🆕 New venue struct: #{inspect(venue)}")

            # Return the venue with the time_text as extra data
            [ok: %{venue: venue, extra_data: %{time_text: time_text}}]
        end
      rescue
        e ->
          Logger.error("❌ Error processing venue #{venue_data["name"]}: #{inspect(e)}")
          Logger.error("❌ Stack trace: #{Exception.format_stacktrace(__STACKTRACE__)}")
          {:error, "Processing error: #{Exception.message(e)}"}
      catch
        kind, reason ->
          Logger.error("❌ Caught #{kind} processing venue #{venue_data["name"]}: #{inspect(reason)}")
          Logger.error("❌ Stack trace: #{Exception.format_stacktrace(__STACKTRACE__)}")
          {:error, "Caught #{kind}: #{inspect(reason)}"}
      end
    end)

    Logger.debug("📊 Raw results from processing: #{inspect(results)}")

    filtered_results = Enum.filter(results, fn result -> result != nil end)
    Logger.info("📊 Finished process_venues with #{length(filtered_results)} venues passing through filter")
    Logger.debug("📊 Filtered results: #{inspect(filtered_results)}")

    filtered_results
  end

  # Helper to find venue by name and address directly in the database
  defp find_venue_by_name_and_address(name, address) when is_binary(name) and is_binary(address) do
    # Extract postcode from address if present (UK postcode format)
    # UK postcodes are typically at the end of the address and follow patterns like "SW6 4UL"
    postcode = case Regex.run(~r/[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}/i, address) do
      [matched_postcode] -> String.trim(matched_postcode)
      nil -> nil
    end

    # Normalize the name for more flexible matching
    normalized_name = name
                      |> String.downcase()
                      |> String.trim()
                      |> String.replace(~r/\s*\([^)]+\)\s*$/, "") # Remove any parenthetical suffixes

    # Normalize the postcode for more robust matching
    normalized_postcode = if postcode do
                            postcode
                            |> String.upcase()
                            |> String.replace(" ", "")
                          else
                            nil
                          end

    Logger.debug("🔍 Extracted postcode from address: #{inspect(postcode)}")
    Logger.debug("🔍 Normalized name: #{normalized_name}, Normalized postcode: #{normalized_postcode}")

    # Try a series of increasingly flexible lookups:
    cond do
      # 1. Try exact name + postcode match (most specific)
      postcode && find_by_exact_name_and_postcode(name, postcode) ->
        venue = find_by_exact_name_and_postcode(name, postcode)
        Logger.debug("✅ Found venue by exact name + postcode: #{venue.name}, #{venue.postcode}")
        venue

      # 2. Try just the postcode (very reliable for UK venues)
      postcode && find_by_exact_postcode(postcode) ->
        venue = find_by_exact_postcode(postcode)
        Logger.debug("✅ Found venue by exact postcode: #{venue.name}, #{venue.postcode}")
        venue

      # 3. Try normalized postcode for flexible matching
      normalized_postcode && find_by_normalized_postcode(normalized_postcode) ->
        venue = find_by_normalized_postcode(normalized_postcode)
        Logger.debug("✅ Found venue by normalized postcode: #{venue.name}, #{venue.postcode}")
        venue

      # 4. Try normalized name + similar postcode
      normalized_postcode && find_by_normalized_name_and_similar_postcode(normalized_name, normalized_postcode) ->
        venue = find_by_normalized_name_and_similar_postcode(normalized_name, normalized_postcode)
        Logger.debug("✅ Found venue by normalized name + similar postcode: #{venue.name}, #{venue.postcode}")
        venue

      # 5. If all postcode-based lookups fail, try the address fallback
      true ->
        Logger.debug("⚠️ All postcode lookup strategies failed, trying address fallback")
        fallback_address_lookup(name, address)
    end
  end
  defp find_venue_by_name_and_address(_, _), do: nil

  # Find a venue by exact name and postcode match
  defp find_by_exact_name_and_postcode(name, postcode) do
    Logger.debug("🔍 Attempting lookup by exact name + postcode: #{name}, #{postcode}")
    Repo.one(from v in TriviaAdvisor.Locations.Venue,
      where: v.name == ^name and v.postcode == ^postcode,
      limit: 1)
  end

  # Find a venue by exact postcode
  defp find_by_exact_postcode(postcode) do
    Logger.debug("🔍 Attempting lookup by exact postcode: #{postcode}")
    Repo.one(from v in TriviaAdvisor.Locations.Venue,
      where: v.postcode == ^postcode,
      limit: 1)
  end

  # Find a venue by normalized postcode (no spaces, uppercase)
  defp find_by_normalized_postcode(normalized_postcode) do
    Logger.debug("🔍 Attempting lookup by normalized postcode: #{normalized_postcode}")
    Repo.one(from v in TriviaAdvisor.Locations.Venue,
      where: fragment("REPLACE(UPPER(?), ' ', '')", v.postcode) == ^normalized_postcode,
      limit: 1)
  end

  # Find a venue by normalized name and similar postcode
  defp find_by_normalized_name_and_similar_postcode(normalized_name, normalized_postcode) do
    Logger.debug("🔍 Attempting lookup by normalized name + similar postcode: #{normalized_name}, #{normalized_postcode}")
    # We look for venues where:
    # 1. The normalized name is similar (using LIKE for fuzzy matching)
    # 2. The normalized postcode is similar (also using LIKE)
    Repo.one(from v in TriviaAdvisor.Locations.Venue,
      where: fragment("LOWER(?) LIKE ?", v.name, ^"%#{normalized_name}%") and
             fragment("REPLACE(UPPER(?), ' ', '') LIKE ?", v.postcode, ^"%#{normalized_postcode}%"),
      limit: 1)
  end

  # Fallback for when postcode lookup doesn't work
  defp fallback_address_lookup(name, address) do
    Logger.debug("🔍 Trying exact address match: #{name}, #{address}")
    # First try exact match
    case Repo.one(from v in TriviaAdvisor.Locations.Venue,
          where: v.name == ^name and v.address == ^address,
          limit: 1) do
      nil ->
        # If no exact match, normalize and try more flexible matching
        Logger.debug("⚠️ Exact address match failed, trying flexible match")
        normalized_name = name |> String.downcase() |> String.trim()
        normalized_address = address |> String.downcase() |> String.trim() |> String.replace(~r/\s+/, " ")

        # Try a fuzzy match with both name and address patterns
        Logger.debug("🔍 Trying flexible match with normalized values")
        venue = Repo.one(from v in TriviaAdvisor.Locations.Venue,
          where: fragment("LOWER(?) LIKE ?", v.name, ^"#{normalized_name}%") and
                 fragment("LOWER(?) LIKE ?", v.address, ^"%#{normalized_address}%"),
          limit: 1)

        if venue do
          Logger.debug("✅ Found venue with flexible match: #{venue.name}, #{venue.address}")
        else
          Logger.debug("❌ No venue found with any matching strategy")
        end

        venue
      venue ->
        Logger.debug("✅ Found venue with exact address match: #{venue.name}, #{venue.address}")
        venue
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

  @doc """
  Test function to expose find_venue_by_name_and_address for tests
  """
  def test_find_venue(name, address) do
    case find_venue_by_name_and_address(name, address) do
      nil -> {:error, :not_found}
      venue -> {:ok, venue}
    end
  end

  @doc """
  Test function to expose load_existing_sources for tests
  """
  def test_load_existing_sources(source_id) do
    load_existing_sources(source_id)
  end

  @doc """
  Test function to expose should_process_venue? for tests
  """
  def test_should_process_venue?(venue, existing_sources_by_venue) do
    should_process_venue?(venue, existing_sources_by_venue)
  end

  @doc """
  Test function to expose venue key generation for tests
  """
  def test_venue_key(name, address) do
    generate_venue_key(name, address)
  end
end

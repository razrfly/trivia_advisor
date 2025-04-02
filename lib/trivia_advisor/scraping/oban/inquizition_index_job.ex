defmodule TriviaAdvisor.Scraping.Oban.InquizitionIndexJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob
  alias TriviaAdvisor.Scraping.RateLimiter
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting Inquizition Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Check if we should force update all venues
    force_update = RateLimiter.force_update?(args)
    force_refresh_images = Map.get(args, "force_refresh_images", false)

    if force_update do
      Logger.info("⚠️ Force update enabled - will process ALL venues regardless of last update time")
    end

    if force_refresh_images do
      Logger.info("⚠️ Force refresh images enabled - will refresh all venue images")
    end

    # Get the Inquizition source
    source = Repo.get_by!(Source, name: "inquizition")
    Logger.debug("📊 Found source: #{inspect(source)}")

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

        # Filter venues that should be processed based on last_seen_at
        {to_process, to_skip} = if force_update do
          # If force_update is true, process all venues
          Logger.info("🔄 Force update enabled - processing ALL venues")
          {venues_to_process, []}
        else
          # IMPORTANT FIX: Don't filter based on last_seen_at for this scraper
          # The heavy lifting is already done at this point, and the complex venue matching is more important
          # We're processing all venues by default unless force_update is specified
          Logger.info("🔄 Inquizition scraper processes all venues by default - not filtering by last_seen_at")
          {venues_to_process, []}
        end

        processed_count = length(to_process)
        skipped_count = length(to_skip)

        Logger.info("🧮 After filtering: Processing #{processed_count} venues, skipping #{skipped_count} venues")
        Logger.debug("📊 Venues to process: #{inspect(to_process)}")

        # Log which venues are being skipped (none in this case unless force_update is false)
        Enum.each(to_skip, fn venue_data ->
          _venue_key = generate_venue_key(venue_data["name"], venue_data["address"])
          Logger.info("⏩ Skipping venue '#{venue_data["name"]}' - recently seen")
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

            Logger.debug("📦 Created venue_data for job: #{inspect(venue_data)}")

            # Create the job with proper arguments including flags
            job = %{
              "venue_data" => venue_data,
              "force_update" => force_update,
              "force_refresh_images" => force_refresh_images
            }
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

        # Use JobMetadata helper instead of direct SQL
        JobMetadata.update_index_job(job_id, metadata)

    {:ok, %{
      venue_count: total_venues,
          enqueued_jobs: enqueued_count,
          skipped_venues: skipped_count
        }}

      {:error, reason} ->
        # Handle the error case
        Logger.error("❌ Failed to fetch Inquizition venues: #{inspect(reason)}")

        # Update job metadata with error using JobMetadata helper
        JobMetadata.update_error(job_id, reason, context: %{source_id: source.id})

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

    # Try a series of increasingly flexible lookups:
    cond do
      # 1. Try exact name + postcode match (most specific)
      postcode && find_by_exact_name_and_postcode(name, postcode) ->
        find_by_exact_name_and_postcode(name, postcode)

      # 2. Try just the postcode (very reliable for UK venues)
      postcode && find_by_exact_postcode(postcode) ->
        find_by_exact_postcode(postcode)

      # 3. Try normalized postcode for flexible matching
      normalized_postcode && find_by_normalized_postcode(normalized_postcode) ->
        find_by_normalized_postcode(normalized_postcode)

      # 4. Try normalized name + similar postcode
      normalized_postcode && find_by_normalized_name_and_similar_postcode(normalized_name, normalized_postcode) ->
        find_by_normalized_name_and_similar_postcode(normalized_name, normalized_postcode)

      # 5. If all postcode-based lookups fail, try the address fallback
      true ->
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
    # First try exact match
    case Repo.one(from v in TriviaAdvisor.Locations.Venue,
          where: v.name == ^name and v.address == ^address,
          limit: 1) do
      nil ->
        # If no exact match, normalize and try more flexible matching
        normalized_name = name |> String.downcase() |> String.trim()
        normalized_address = address |> String.downcase() |> String.trim() |> String.replace(~r/\s+/, " ")

        # Try a fuzzy match with both name and address patterns
        Repo.one(from v in TriviaAdvisor.Locations.Venue,
          where: fragment("LOWER(?) LIKE ?", v.name, ^"#{normalized_name}%") and
                 fragment("LOWER(?) LIKE ?", v.address, ^"%#{normalized_address}%"),
          limit: 1)
      venue -> venue
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

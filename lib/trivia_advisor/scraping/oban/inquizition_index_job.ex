defmodule TriviaAdvisor.Scraping.Oban.InquizitionIndexJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Events.Event
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting Inquizition Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Get the Inquizition source
    source = Repo.get_by!(Source, name: "inquizition")

    # Call the existing scraper function - we don't modify this
    results = Scraper.scrape()

    # Count total venues found
    total_venues = length(results)
    Logger.info("📊 Found #{total_venues} total venues from Inquizition")

    # Load existing venues and their events for comparison
    existing_venues_with_events = load_existing_venues_with_events(source.id)

    # Limit venues if needed (for testing)
    venues_to_process = if limit, do: Enum.take(results, limit), else: results

    # For each venue, check if we need to process it based on venue or event changes
    venues_to_enqueue = venues_to_process
    |> Enum.filter(fn [ok: venue] ->
      should_process_venue?(venue, existing_venues_with_events)
    end)

    detail_jobs = enqueue_detail_jobs(venues_to_enqueue, source.id)

    Logger.info("📥 Enqueued #{length(detail_jobs)} Inquizition detail jobs")

    {:ok, %{
      venue_count: total_venues,
      enqueued_jobs: length(detail_jobs)
    }}
  end

  # Load existing venues and their events for comparison
  defp load_existing_venues_with_events(source_id) do
    # Query for venues and their events from this source
    query = from v in Venue,
      left_join: e in Event, on: e.venue_id == v.id and e.source_id == ^source_id,
      where: not is_nil(v.address),
      select: {v, e}

    Repo.all(query)
    |> Enum.group_by(
      fn {venue, _} -> normalize_address(venue.address) end,
      fn {venue, event} -> {venue, event} end
    )
  end

  # Check if venue needs processing either because it's new or event details changed
  defp should_process_venue?(venue, existing_venues_with_events) do
    normalized_address = normalize_address(venue.address)

    case Map.get(existing_venues_with_events, normalized_address) do
      nil ->
        # New venue - should always process
        Logger.debug("🆕 New venue found: #{venue.name} - #{venue.address}")
        true

      venue_events ->
        # Check if any event details have changed
        current_day = extract_day_of_week(venue)
        current_time = extract_start_time(venue)

        any_changes = Enum.any?(venue_events, fn {existing_venue, event} ->
          event_changed?(existing_venue, event, venue, current_day, current_time)
        end)

        if any_changes do
          Logger.debug("🔄 Event details changed for venue: #{venue.name} - processing")
          true
        else
          Logger.debug("⏩ Skipping venue with unchanged events: #{venue.name}")
          false
        end
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

  # Check if the event details have changed
  defp event_changed?(_existing_venue, nil, _new_venue, _new_day, _new_time) do
    # No existing event - this is a change
    true
  end

  defp event_changed?(_existing_venue, existing_event, _new_venue, new_day, new_time) do
    # Compare day and time to see if anything changed
    existing_day = existing_event.day_of_week
    existing_time = existing_event.start_time

    day_changed = existing_day != new_day && !is_nil(new_day)
    time_changed = existing_time != new_time && !is_nil(new_time)

    if day_changed do
      Logger.debug("📅 Day of week changed: #{existing_day} -> #{new_day}")
    end

    if time_changed do
      Logger.debug("🕒 Start time changed: #{existing_time} -> #{new_time}")
    end

    day_changed || time_changed
  end

  # Address normalization function
  defp normalize_address(address) when is_binary(address) do
    address
    |> String.downcase()
    |> String.replace(~r/\s+/, " ") # Remove extra spaces
    |> String.trim()
  end
  defp normalize_address(nil), do: ""

  # Enqueue detail jobs for venues that need processing
  defp enqueue_detail_jobs(venues_to_process, source_id) do
    Enum.map(venues_to_process, fn [ok: venue] ->
      # Extract all required venue details
      venue_data = %{
        "name" => venue.name,
        "address" => venue.address,
        "phone" => venue.phone,
        "website" => venue.website,
        "source_id" => source_id,
        "time_text" => Map.get(venue, :time_text) || "",
        "day_of_week" => Map.get(venue, :day_of_week),
        "start_time" => Map.get(venue, :start_time),
        "frequency" => Map.get(venue, :frequency) || "weekly",
        "entry_fee" => Map.get(venue, :entry_fee) || "2.50",
        "description" => Map.get(venue, :description),
        "hero_image" => Map.get(venue, :hero_image),
        "hero_image_url" => Map.get(venue, :hero_image_url),
        "facebook" => Map.get(venue, :facebook),
        "instagram" => Map.get(venue, :instagram),
        "source_url" => Map.get(venue, :source_url) || ""
      }

      # Create job from venue data - Note: Keep the "venue_data" wrapper as that's what the DetailJob expects
      job_result = InquizitionDetailJob.new(%{
        "venue_data" => venue_data
      })

      # Handle all possible job creation results
      job = case job_result do
        {:ok, job} -> job
        %Ecto.Changeset{valid?: true} = changeset -> changeset
        other ->
          Logger.error("❌ Unexpected job creation result for venue #{venue.name}: #{inspect(other)}")
          nil
      end

      # Insert the job if we got a valid job or changeset
      if job do
        Logger.debug("📥 Enqueuing detail job for venue: #{venue.name}")

        # Insert the job
        case Oban.insert(job) do
          {:ok, _oban_job} ->
            Logger.debug("✓ Job successfully inserted for venue: #{venue.name}")
            venue.name
          {:error, error} ->
            Logger.error("❌ Failed to insert job for venue #{venue.name}: #{inspect(error)}")
            nil
          other ->
            Logger.error("❌ Unexpected result when inserting job for venue #{venue.name}: #{inspect(other)}")
            nil
        end
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end

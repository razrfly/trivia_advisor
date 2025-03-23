defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Quizmeisters.VenueExtractor
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer, Event}
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob
  alias TriviaAdvisor.Events.EventSource

  # Increased timeout values to prevent hanging requests
  @http_options [
    follow_redirect: true,
    timeout: 30_000,        # 30 seconds for connect timeout
    recv_timeout: 30_000,   # 30 seconds for receive timeout
    hackney: [pool: false]  # Don't use connection pooling for scrapers
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"venue" => venue_data, "source_id" => source_id}}) do
    Logger.info("🔄 Processing venue: #{venue_data["name"]}")
    source = Repo.get!(Source, source_id)

    # Special handling for the 3rd Space Canberra venue
    if venue_data["name"] == "3rd Space Canberra" do
      Logger.info("🔍 Special handling for 3rd Space Canberra")

      # Find the event for this venue
      venue = Repo.get_by(Venue, name: "3rd Space Canberra")
      if venue do
        # Use proper Ecto syntax
        import Ecto.Query
        event = Repo.one(from e in Event, where: e.venue_id == ^venue.id, limit: 1)

        if event do
          # Force update the timestamp directly
          JobMetadata.force_update_event_source_timestamp(event.id, source_id, normalize_quizmeisters_url(venue_data["url"]))
        end
      end
    end

    # Process the venue and event using existing code patterns
    case process_venue(venue_data, source) do
      {:ok, %{venue: venue, final_data: final_data} = result} ->
        # Extract event data from any possible structure formats
        {event_id, _event} = normalize_event_result(result[:event])

        Logger.info("✅ Successfully processed venue: #{venue.name}")

        # Add timestamps and result data to final_data for metadata
        metadata = final_data
          |> Map.take([:name, :address, :phone, :day_of_week, :start_time, :frequency, :url, :description])
          |> Map.put(:venue_id, venue.id)
          |> Map.put(:event_id, event_id)
          |> Map.put(:source_id, source_id)
          |> Map.put(:processed_at, DateTime.utc_now() |> DateTime.to_iso8601())

        # Convert to string keys for consistency
        string_metadata = for {key, val} <- metadata, into: %{} do
          {"#{key}", val}
        end

        result_data = {:ok, %{venue_id: venue.id, event_id: event_id}}
        JobMetadata.update_detail_job(job_id, string_metadata, result_data, source_id: source_id)
        result_data

      {:ok, %{venue: venue} = result} ->
        # Handle case where final_data is not available
        {event_id, _event} = normalize_event_result(result[:event])

        Logger.info("✅ Successfully processed venue: #{venue.name}")

        # Create minimal metadata with available info
        metadata = %{
          "venue_name" => venue.name,
          "venue_id" => venue.id,
          "event_id" => event_id,
          "source_id" => source_id,
          "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        result_data = {:ok, %{venue_id: venue.id, event_id: event_id}}
        JobMetadata.update_detail_job(job_id, metadata, result_data, source_id: source_id)
        result_data

      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        JobMetadata.update_error(job_id, reason, context: %{"venue" => venue_data["name"]})
        {:error, reason}
    end
  end

  # Helper to normalize different event result structures into consistent id and map
  defp normalize_event_result(event_data) do
    case event_data do
      {:ok, %{event: event}} when is_map(event) -> {event.id, event}
      {:ok, event} when is_map(event) -> {event.id, event}
      %{event: event} when is_map(event) -> {event.id, event}
      event when is_map(event) -> {event.id, event}
    end
  end

  # Process venue - adapted from Quizmeisters scraper
  defp process_venue(location, source) do
    # First, parse the venue data (similar to parse_venue in original scraper)
    time_text = get_trivia_time(location)

    # If time_text is empty, try to find the day from fields
    time_text = if time_text == "" do
      find_trivia_day_from_fields(location)
    else
      time_text
    end

    # If we still can't determine a day/time, use a default value
    time_text = if time_text == "" do
      Logger.warning("⚠️ No trivia day/time found for venue: #{location["name"]}. Attempting to proceed with defaults.")
      # Default to Thursday 7:00 PM as a fallback to allow processing
      "Thursday 7:00 PM"
    else
      time_text
    end

    case TimeParser.parse_time_text(time_text) do
      {:ok, %{day_of_week: day_of_week, start_time: start_time}} ->
        # Build the venue data for processing
        venue_data = %{
          raw_title: location["name"],
          title: location["name"],
          name: location["name"],
          address: location["address"],
          time_text: time_text,
          day_of_week: day_of_week,
          start_time: start_time,
          frequency: :weekly,
          fee_text: "Free", # All Quizmeisters events are free
          phone: location["phone"],
          website: nil, # Will be fetched from individual venue page
          description: nil, # Will be fetched from individual venue page
          hero_image: nil,
          hero_image_url: nil, # Will be fetched from individual venue page
          url: location["url"],
          facebook: nil, # Will be fetched from individual venue page
          instagram: nil, # Will be fetched from individual venue page
          latitude: location["lat"],
          longitude: location["lng"],
          postcode: location["postcode"]
        }

        # Log venue details
        VenueHelpers.log_venue_details(venue_data)

        # Fetch venue details from the venue page
        case fetch_venue_details(venue_data, source) do
          {:ok, result} ->
            {:ok, result}
          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to parse time text: #{reason} for #{location["name"]}")
        Logger.error("Time text was: '#{time_text}'")
        {:error, reason}
    end
  end

  # Extract trivia time from location data - improved to better handle missing data
  defp get_trivia_time(%{"custom_fields" => custom_fields}) when is_map(custom_fields) do
    case Map.get(custom_fields, "trivia_night") do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _ -> ""
    end
  end
  defp get_trivia_time(_), do: ""

  # Try to find trivia day from fields array
  defp find_trivia_day_from_fields(%{"fields" => fields}) when is_list(fields) do
    # Look for a field that might contain day information
    trivia_field = Enum.find(fields, fn field ->
      name = Map.get(field, "name", "")
      value = Map.get(field, "value", "")

      is_binary(name) and is_binary(value) and
      (String.contains?(String.downcase(name), "trivia") or
       String.contains?(String.downcase(name), "quiz"))
    end)

    case trivia_field do
      %{"value" => value} when is_binary(value) and byte_size(value) > 0 -> value
      _ -> ""
    end
  end
  defp find_trivia_day_from_fields(_), do: ""

  # Fetch venue details - adapted from Quizmeisters scraper
  defp fetch_venue_details(venue_data, source) do
    Logger.info("Processing venue: #{venue_data.title}")

    # Start a task with timeout to handle hanging HTTP requests
    task = Task.async(fn ->
      case HTTPoison.get(venue_data.url, [], @http_options) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          with {:ok, document} <- Floki.parse_document(body),
               {:ok, extracted_data} <- VenueExtractor.extract_venue_data(document, venue_data.url, venue_data.raw_title) do

            # First merge the extracted data with the API data
            merged_data = Map.merge(venue_data, extracted_data)

            # Then process through VenueStore with social media data
            venue_store_data = %{
              name: merged_data.name,
              address: merged_data.address,
              phone: merged_data.phone,
              website: merged_data.website,
              facebook: merged_data.facebook,
              instagram: merged_data.instagram,
              latitude: merged_data.latitude,
              longitude: merged_data.longitude,
              postcode: merged_data.postcode
            }

            case VenueStore.process_venue(venue_store_data) do
              {:ok, venue} ->
                # Schedule a separate job for Google Place lookup
                Logger.info("🔄 Scheduling Google Place lookup job for venue: #{venue.name}")
                schedule_place_lookup(venue)

                final_data = Map.put(merged_data, :venue_id, venue.id)
                VenueHelpers.log_venue_details(final_data)

                # Process performer if present - add detailed logging
                performer_id = case final_data.performer do
                  # Case 1: Complete performer data with name and image
                  %{name: name, profile_image: image_url} when not is_nil(name) and is_binary(image_url) and image_url != "" ->
                    Logger.info("🎭 Found complete performer data for #{venue.name}: Name: #{name}, Image URL: #{String.slice(image_url, 0, 50)}...")

                    # Use a timeout for image downloads too
                    case safe_download_performer_image(image_url) do
                      {:ok, profile_image} when not is_nil(profile_image) ->
                        Logger.info("📸 Successfully downloaded performer image for #{name}")

                        # Create or update performer - with timeout protection
                        performer_attrs = %{
                          name: name,
                          profile_image: profile_image,
                          source_id: source.id
                        }

                        Logger.debug("🎭 Performer attributes: #{inspect(performer_attrs)}")

                        # Wrap performer creation in a Task with timeout to prevent it from blocking the job
                        performer_task = Task.async(fn ->
                          Performer.find_or_create(performer_attrs)
                        end)

                        case Task.yield(performer_task, 30_000) || Task.shutdown(performer_task) do
                          {:ok, {:ok, performer}} ->
                            Logger.info("✅ Successfully created/updated performer #{performer.id} (#{performer.name}) for venue #{venue.name}")
                            performer.id
                          {:ok, {:error, changeset}} ->
                            Logger.error("❌ Failed to create/update performer: #{inspect(changeset.errors)}")
                            nil
                          _ ->
                            Logger.error("⏱️ Timeout creating/updating performer for #{name}")
                            nil
                        end
                      {:ok, nil} ->
                        # Image download returned nil but not an error
                        Logger.warning("⚠️ Image download returned nil for performer #{name}, proceeding without image")

                        # Try to create performer without image
                        performer_attrs = %{
                          name: name,
                          source_id: source.id
                        }

                        case Performer.find_or_create(performer_attrs) do
                          {:ok, performer} ->
                            Logger.info("✅ Created performer #{performer.id} without image")
                            performer.id
                          _ ->
                            nil
                        end
                      {:error, reason} ->
                        Logger.error("❌ Failed to download performer image: #{inspect(reason)}")
                        nil
                    end

                  # Case 2: Performer with name only
                  %{name: name} when not is_nil(name) and is_binary(name) ->
                    # Check for empty strings after pattern matching
                    if String.trim(name) != "" do
                      Logger.info("🎭 Found performer with name only for #{venue.name}: Name: #{name}")

                      # Create performer without image
                      performer_attrs = %{
                        name: name,
                        source_id: source.id
                      }

                      case Performer.find_or_create(performer_attrs) do
                        {:ok, performer} ->
                          Logger.info("✅ Created performer #{performer.id} (#{performer.name}) without image")
                          performer.id
                        {:error, reason} ->
                          Logger.error("❌ Failed to create performer: #{inspect(reason)}")
                          nil
                      end
                    else
                      Logger.info("ℹ️ Empty performer name for #{venue.name}, skipping")
                      nil
                    end

                  # Case 3: Performer with image only
                  %{profile_image: image_url} when is_binary(image_url) and image_url != "" ->
                    Logger.info("🎭 Found performer with image only for #{venue.name}")

                    # Use a generated name based on venue
                    generated_name = "#{venue.name} Host"

                    # Download image and create performer with generated name
                    case safe_download_performer_image(image_url) do
                      {:ok, profile_image} when not is_nil(profile_image) ->
                        Logger.info("📸 Successfully downloaded performer image for #{generated_name}")

                        performer_attrs = %{
                          name: generated_name,
                          profile_image: profile_image,
                          source_id: source.id
                        }

                        case Performer.find_or_create(performer_attrs) do
                          {:ok, performer} ->
                            Logger.info("✅ Created performer #{performer.id} (#{performer.name}) with image but generated name")
                            performer.id
                          {:error, reason} ->
                            Logger.error("❌ Failed to create performer: #{inspect(reason)}")
                            nil
                        end

                      {:ok, nil} ->
                        Logger.warning("⚠️ Image download returned nil for performer with no name, skipping")
                        nil

                      {:error, reason} ->
                        Logger.error("❌ Failed to download performer image: #{inspect(reason)}")
                        nil
                    end

                  # Case 4: We have performer information but it's nil
                  nil ->
                    Logger.info("ℹ️ No performer data found for #{venue.name}")
                    nil

                  # Case 5: Any other malformed performer data
                  other ->
                    Logger.warning("⚠️ Invalid performer data format for #{venue.name}: #{inspect(other)}")
                    nil
                end

                # Process the event using EventStore like QuestionOne
                # IMPORTANT: Use string keys for the event_data map to ensure compatibility with EventStore.process_event
                event_data = %{
                  "raw_title" => final_data.raw_title,
                  "name" => venue.name,
                  "time_text" => format_time_text(final_data.day_of_week, final_data.start_time),
                  "description" => final_data.description,
                  "fee_text" => "Free", # All Quizmeisters events are free
                  "hero_image_url" => final_data.hero_image_url,
                  "source_url" => normalize_quizmeisters_url(venue_data.url),
                  "performer_id" => performer_id
                }

                # Log whether we have a performer_id
                if performer_id do
                  Logger.info("🎭 Adding performer_id #{performer_id} to event for venue #{venue.name}")
                else
                  Logger.info("⚠️ No performer_id for event at venue #{venue.name}")
                end

                # Directly update an existing event if it exists
                existing_event = find_existing_event(venue.id, final_data.day_of_week)

                if existing_event && performer_id do
                  # If we have an existing event and a performer, update the performer_id directly
                  Logger.info("🔄 Found existing event #{existing_event.id} for venue #{venue.name}, updating performer_id to #{performer_id}")

                  case existing_event
                       |> Ecto.Changeset.change(%{performer_id: performer_id})
                       |> Repo.update() do
                    {:ok, updated_event} ->
                      Logger.info("✅ Successfully updated existing event #{updated_event.id} with performer_id #{updated_event.performer_id}")

                      # Update the event source's last_seen_at timestamp
                      Logger.info("🔄 Updating event source's last_seen_at timestamp")
                      now = DateTime.utc_now()

                      case Repo.get_by(EventSource, event_id: updated_event.id, source_id: source.id) do
                        nil ->
                          Logger.error("❌ No event source found for event #{updated_event.id} and source #{source.id}")
                        event_source ->
                          Logger.info("🔄 Updating existing event_source #{event_source.id} with last_seen_at: #{DateTime.to_string(now)}")

                          # Build metadata similar to what EventStore.upsert_event_source would do
                          metadata = %{
                            raw_title: event_data["raw_title"],
                            clean_title: event_data["name"],
                            address: venue.address,
                            time_text: event_data["time_text"],
                            day_of_week: final_data.day_of_week,
                            start_time: final_data.start_time,
                            frequency: final_data.frequency,
                            fee_text: event_data["fee_text"],
                            phone: venue.phone,
                            website: venue.website,
                            description: event_data["description"],
                            hero_image_url: event_data["hero_image_url"]
                          }

                          # Normalize the source URL consistently
                          source_url = normalize_quizmeisters_url(venue_data.url)

                          event_source
                          |> EventSource.changeset(%{
                            source_url: source_url,
                            metadata: metadata,
                            last_seen_at: now
                          })
                          |> Repo.update()
                          |> case do
                            {:ok, updated_source} ->
                              Logger.info("✅ Successfully updated event_source last_seen_at to #{DateTime.to_string(updated_source.last_seen_at)}")
                            {:error, error} ->
                              Logger.error("❌ Failed to update event_source: #{inspect(error)}")
                          end
                      end

                      # Include final_data in the return value
                      {:ok, %{venue: venue, event: updated_event, final_data: final_data}}
                    {:error, changeset} ->
                      Logger.error("❌ Failed to update existing event with performer_id: #{inspect(changeset.errors)}")
                      # Continue with normal event processing - note that this result is a tuple with event inside
                      result = process_event_with_performer(venue, event_data, source.id, performer_id)
                      case result do
                        {:ok, result_map} ->
                          # Add final_data to result
                          {:ok, Map.put(result_map, :final_data, final_data)}
                        error -> error
                      end
                  end
                else
                  # No existing event or no performer, proceed with normal event processing
                  result = process_event_with_performer(venue, event_data, source.id, performer_id)
                  case result do
                    {:ok, result_map} ->
                      # Add final_data to result
                      {:ok, Map.put(result_map, :final_data, final_data)}
                    error -> error
                  end
                end

              error ->
                Logger.error("Failed to process venue: #{inspect(error)}")
                {:error, error}
            end
          else
            {:error, reason} ->
              Logger.error("Failed to extract venue data: #{reason}")
              {:error, reason}
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          Logger.error("HTTP #{status} when fetching venue: #{venue_data.url}")
          {:error, "HTTP #{status}"}

        {:error, %HTTPoison.Error{reason: :timeout}} ->
          Logger.error("Timeout fetching venue #{venue_data.url}")
          {:error, "HTTP request timeout"}

        {:error, %HTTPoison.Error{reason: :connect_timeout}} ->
          Logger.error("Connection timeout fetching venue #{venue_data.url}")
          {:error, "HTTP connection timeout"}

        {:error, error} ->
          Logger.error("Error fetching venue #{venue_data.url}: #{inspect(error)}")
          {:error, error}
      end
    end)

    # Wait for the task with a longer timeout
    case Task.yield(task, 60_000) || Task.shutdown(task) do
      {:ok, result} -> result
      nil ->
        Logger.error("Task timeout when processing venue: #{venue_data.title}")
        {:error, "Task timeout"}
    end
  end

  # Find an existing event by venue_id and day_of_week
  defp find_existing_event(venue_id, day_of_week) do
    import Ecto.Query

    Repo.one(
      from e in Event,
      where: e.venue_id == ^venue_id and
             e.day_of_week == ^day_of_week,
      limit: 1
    )
  end

  # Process event with performer_id with timeout protection
  defp process_event_with_performer(venue, event_data, source_id, performer_id) do
    # Log the event data and performer_id before processing
    Logger.debug("🎭 Processing event with performer_id: #{inspect(performer_id)}")
    Logger.debug("🎭 Event data: #{inspect(Map.take(event_data, ["raw_title", "name", "performer_id"]))}")

    # Process the event with timeout protection
    event_task = Task.async(fn ->
      EventStore.process_event(venue, event_data, source_id)
    end)

    # Use a generous timeout for event processing
    result = case Task.yield(event_task, 45_000) || Task.shutdown(event_task) do
      {:ok, result} -> result
      nil ->
        Logger.error("⏱️ Timeout in EventStore.process_event for venue #{venue.name}")
        {:error, "EventStore.process_event timeout"}
    end

    Logger.info("🎭 EventStore.process_event result: #{inspect(result)}")

    case result do
      # Handle nested OK tuple: {:ok, {:ok, event}}
      {:ok, {:ok, event}} ->
        Logger.info("✅ Successfully processed event #{event.id} for venue #{venue.name}")

        # Check if performer_id needs to be updated
        if not is_nil(performer_id) and (is_nil(event.performer_id) or event.performer_id != performer_id) do
          Logger.info("🔄 Adding performer_id #{performer_id} to event #{event.id}")

          case event
               |> Ecto.Changeset.change(%{performer_id: performer_id})
               |> Repo.update() do
            {:ok, updated_event} ->
              Logger.info("✅ Successfully updated event with performer_id #{performer_id}")
              {:ok, %{venue: venue, event: updated_event}}
            {:error, changeset} ->
              Logger.error("❌ Failed to update event with performer_id: #{inspect(changeset.errors)}")
              {:ok, %{venue: venue, event: event}}
          end
        else
          {:ok, %{venue: venue, event: event}}
        end

      # Handle direct OK event return: {:ok, event}
      {:ok, event} when is_map(event) ->
        Logger.info("✅ Successfully processed event #{event.id} for venue #{venue.name}")

        # Check if performer_id needs to be updated
        if not is_nil(performer_id) and (is_nil(event.performer_id) or event.performer_id != performer_id) do
          Logger.info("🔄 Adding performer_id #{performer_id} to event #{event.id}")

          case event
               |> Ecto.Changeset.change(%{performer_id: performer_id})
               |> Repo.update() do
            {:ok, updated_event} ->
              Logger.info("✅ Successfully updated event with performer_id #{performer_id}")
              {:ok, %{venue: venue, event: updated_event}}
            {:error, changeset} ->
              Logger.error("❌ Failed to update event with performer_id: #{inspect(changeset.errors)}")
              {:ok, %{venue: venue, event: event}}
          end
        else
          {:ok, %{venue: venue, event: event}}
        end

      # Handle error cases
      {:error, reason} ->
        Logger.error("❌ Failed to process event: #{inspect(reason)}")
        {:error, reason}

      # Handle unexpected results
      unexpected ->
        Logger.error("❌ Unexpected result from EventStore.process_event: #{inspect(unexpected)}")
        {:error, "Unexpected result from EventStore.process_event"}
    end
  end

  # Safe wrapper around ImageDownloader.download_performer_image with timeout
  defp safe_download_performer_image(url) do
    # Skip nil URLs early
    if is_nil(url) or String.trim(url) == "" do
      {:error, "Invalid image URL"}
    else
      task = Task.async(fn ->
        case ImageDownloader.download_performer_image(url) do
          nil -> nil
          result ->
            # Ensure the filename has a proper extension
            extension = case Path.extname(url) do
              "" -> ".jpg"  # Default to jpg if no extension
              ext -> ext
            end

            # If result is a Plug.Upload struct, ensure it has the extension
            if is_map(result) && Map.has_key?(result, :filename) && !String.contains?(result.filename, ".") do
              Logger.debug("📸 Adding extension #{extension} to filename: #{result.filename}")
              %{result | filename: result.filename <> extension}
            else
              result
            end
        end
      end)

      # Increase timeout for image downloads
      case Task.yield(task, 40_000) || Task.shutdown(task) do
        {:ok, result} ->
          # Handle any result (including nil)
          {:ok, result}
        _ ->
          Logger.error("Timeout or error downloading performer image from #{url}")
          # Return nil instead of error to allow processing to continue
          {:ok, nil}
      end
    end
  end

  # Format time text - adapted from Quizmeisters scraper
  defp format_time_text(day_of_week, start_time) do
    day_name = case day_of_week do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> ""
    end

    "#{day_name} #{start_time}"
  end

  # Schedules a separate job for Google Place API lookups
  defp schedule_place_lookup(venue) do
    # Create a job with the venue ID
    %{"venue_id" => venue.id}
    |> GooglePlaceLookupJob.new()
    |> Oban.insert()
  end

  # Normalize Quizmeisters URLs to a consistent format
  # This helps match URLs across different formats (with/without www, .com vs .com.au, etc.)
  defp normalize_quizmeisters_url(url) when is_binary(url) do
    Logger.info("🔗 Normalizing URL: #{url}")

    # Extract the venue slug from the URL for better matching
    venue_slug = case Regex.run(~r{/venues/([^/]+)/?$}, url) do
      [_, slug] -> slug
      _ -> nil
    end

    # Standardize the URL format
    normalized_url = url
      |> String.replace("http://", "https://")
      |> ensure_www_prefix()

    # If we found a venue slug, use it to lookup existing event sources with similar URLs
    if venue_slug do
      # Check if we have any existing event sources with URLs containing the venue slug
      # This helps handle cases where the URL format has changed (e.g., prefix changes)
      venue_key = venue_slug |> String.replace(~r{^(act|nsw|qld|vic|sa|wa|tas|nt)-}, "")

      # Try to find an existing event source with a URL containing this venue key
      existing_source_url = find_event_source_with_venue_key(venue_key)

      if existing_source_url do
        Logger.info("🔗 Found existing event source with URL: #{existing_source_url}")
        existing_source_url
      else
        Logger.info("🔗 Normalized URL: #{normalized_url}")
        normalized_url
      end
    else
      Logger.info("🔗 Normalized URL: #{normalized_url}")
      normalized_url
    end
  end

  defp normalize_quizmeisters_url(nil), do: nil

  # Ensure URL has www. prefix for consistency
  defp ensure_www_prefix(url) do
    if String.contains?(url, "://www.") do
      url
    else
      url |> String.replace("://", "://www.")
    end
  end

  # Find an event source with a URL containing the given venue key
  defp find_event_source_with_venue_key(venue_key) do
    import Ecto.Query

    # Use ILIKE for case-insensitive matching
    query = from es in EventSource,
            where: like(es.source_url, "%quizmeisters%") and like(es.source_url, ^"%#{venue_key}%"),
            order_by: [desc: es.last_seen_at],
            limit: 1,
            select: es.source_url

    case Repo.one(query) do
      nil -> nil
      url -> url
    end
  end
end

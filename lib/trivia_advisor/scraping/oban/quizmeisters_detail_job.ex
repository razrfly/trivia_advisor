defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    priority: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Quizmeisters.VenueExtractor
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer, Event}
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

  # Increased timeout values to prevent hanging requests
  @http_options [
    follow_redirect: true,
    timeout: 30_000,        # 30 seconds for connect timeout
    recv_timeout: 30_000,   # 30 seconds for receive timeout
    hackney: [pool: false]  # Don't use connection pooling for scrapers
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue" => venue_data, "source_id" => source_id}}) do
    Logger.info("🔄 Processing venue: #{venue_data["name"]}")
    source = Repo.get!(Source, source_id)

    # Process the venue and event using existing code patterns
    case process_venue(venue_data, source) do
      {:ok, %{venue: venue, event: {:ok, event_struct}}} ->
        # Handle the case where event is a tuple
        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event_struct.id}}

      {:ok, %{venue: venue, event: event}} when is_map(event) ->
        # Handle the case where event is already unwrapped
        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      # Handle nested structure cases
      {:ok, %{venue: venue, event: {:ok, %{event: event}}}} ->
        Logger.info("✅ Successfully processed venue: #{venue.name} with nested event result")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      {:ok, %{venue: venue, event: %{event: event}}} ->
        Logger.info("✅ Successfully processed venue: #{venue.name} with map-wrapped event")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        {:error, reason}
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
                final_data = Map.put(merged_data, :venue_id, venue.id)
                VenueHelpers.log_venue_details(final_data)

                # Process performer if present - add detailed logging
                performer_id = case final_data.performer do
                  %{name: name, profile_image: image_url} when not is_nil(name) and is_binary(image_url) and image_url != "" ->
                    Logger.info("🎭 Found performer data for #{venue.name}: Name: #{name}, Image URL: #{String.slice(image_url, 0, 50)}...")

                    # Use a timeout for image downloads too
                    case safe_download_performer_image(image_url) do
                      {:ok, profile_image} ->
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
                  nil ->
                    Logger.info("ℹ️ No performer data found for #{venue.name}")
                    nil
                  _ ->
                    Logger.info("⚠️ Invalid performer data format for #{venue.name}")
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
                  "source_url" => venue_data.url,
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
                      {:ok, %{venue: venue, event: updated_event}}
                    {:error, changeset} ->
                      Logger.error("❌ Failed to update existing event with performer_id: #{inspect(changeset.errors)}")
                      # Continue with normal event processing - note that this result is a tuple with event inside
                      result = process_event_with_performer(venue, event_data, source.id, performer_id)
                      Logger.debug("🔍 Process event with performer result: #{inspect(result)}")
                      result
                  end
                else
                  # No existing event or no performer, proceed with normal event processing
                  result = process_event_with_performer(venue, event_data, source.id, performer_id)
                  Logger.debug("🔍 Process event with performer result: #{inspect(result)}")
                  result
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

    Logger.debug("🎭 EventStore.process_event result: #{inspect(result)}")

    case result do
      {:ok, event} when is_map(event) ->
        # Pattern match succeeded, event is a map as expected
        event_performer_id = Map.get(event, :performer_id)

        # Verify the performer_id was set on the event
        if event_performer_id == performer_id do
          Logger.info("✅ Successfully set performer_id #{performer_id} on event #{event.id}")
          {:ok, %{venue: venue, event: event}}
        else
          Logger.warning("⚠️ Event #{event.id} has performer_id #{event_performer_id} but expected #{performer_id}")

          # Try to update the event directly if performer_id wasn't set
          if not is_nil(performer_id) and (is_nil(event_performer_id) or event_performer_id != performer_id) do
            Logger.info("🔄 Attempting to update event #{event.id} with performer_id #{performer_id}")

            # Direct update to ensure performer_id is set
            case Repo.get(Event, event.id) do
              nil ->
                Logger.error("❌ Could not find event with ID #{event.id}")
                {:ok, %{venue: venue, event: event}}
              event_to_update ->
                event_to_update
                |> Ecto.Changeset.change(%{performer_id: performer_id})
                |> Repo.update()
                |> case do
                  {:ok, updated_event} ->
                    Logger.info("✅ Successfully updated event #{updated_event.id} with performer_id #{updated_event.performer_id}")
                    # Return the updated event instead of the original one
                    {:ok, %{venue: venue, event: updated_event}}
                  {:error, changeset} ->
                    Logger.error("❌ Failed to update event with performer_id: #{inspect(changeset.errors)}")
                    {:ok, %{venue: venue, event: event}}
                end
            end
          else
            Logger.info("✅ Successfully processed event for venue: #{venue.name}")
            {:ok, %{venue: venue, event: event}}
          end
        end

      # Handle unexpected tuple structure (this is the fix for the badkey error)
      {:ok, {:ok, event}} when is_map(event) ->
        Logger.warning("⚠️ Received nested OK tuple, unwrapping event")
        {:ok, %{venue: venue, event: event}}

      # Any other variation of success result
      {:ok, unexpected} ->
        Logger.warning("⚠️ Unexpected event format from EventStore.process_event: #{inspect(unexpected)}")
        # Try to safely proceed
        {:ok, %{venue: venue, event: unexpected}}

      {:error, reason} ->
        Logger.error("❌ Failed to process event: #{inspect(reason)}")
        {:error, reason}

      # Handle completely unexpected result
      unexpected ->
        Logger.error("❌ Completely unexpected result from EventStore.process_event: #{inspect(unexpected)}")
        {:error, "Unexpected result format from EventStore.process_event"}
    end
  end

  # Safe wrapper around ImageDownloader.download_performer_image with timeout
  defp safe_download_performer_image(url) do
    # Skip nil URLs early
    if is_nil(url) or String.trim(url) == "" do
      {:error, "Invalid image URL"}
    else
      task = Task.async(fn -> ImageDownloader.download_performer_image(url) end)

      # Increase timeout for image downloads
      case Task.yield(task, 40_000) || Task.shutdown(task) do
        {:ok, nil} ->
          # Explicit handling for nil result
          {:ok, nil}
        {:ok, result} ->
          # Handle non-nil result
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
end

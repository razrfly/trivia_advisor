defmodule TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkDetailJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.VenueDetailsExtractor
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers, JobMetadata}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer, Event}
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob
  alias HtmlEntities

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    # Extract essential data from args
    venue_data = Map.get(args, "venue")
    source_id = Map.get(args, "source_id")

    # Log relevant job arguments for debugging
    Logger.info("📦 Processing venue: #{venue_data["title"]} (url: #{venue_data["source_url"]}, force_refresh_images: #{Map.get(args, "force_refresh_images", false)})")

    # Extract force_refresh_images with explicit default
    force_refresh_images = Map.get(args, "force_refresh_images", false)

    # CRITICAL: Set the flag explicitly in process dictionary
    if force_refresh_images do
      Logger.info("⚠️ Force image refresh enabled - will refresh ALL images for venue: #{venue_data["title"]}")
      Process.put(:force_refresh_images, true)
    else
      # Explicitly set to false to ensure it's not using a stale value
      Process.put(:force_refresh_images, false)
    end

    # Log the value for verification
    Logger.info("📝 Process dictionary force_refresh_images set to: #{inspect(Process.get(:force_refresh_images))}")

    source = Repo.get!(Source, source_id)

    # Process the venue and event using existing code patterns with explicit flag passing
    case process_venue(venue_data, source, force_refresh_images) do
      {:ok, %{venue: venue, event: event, final_data: final_data}} ->
        # Simply add timestamp and essential IDs to the final_data
        metadata = Map.merge(final_data, %{
          "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "venue_id" => venue.id,
          "event_id" => event.id,
          "force_refresh_images" => force_refresh_images  # Include the flag in metadata
        })

        # Create simple result for return value
        result = %{venue_id: venue.id, event_id: event.id}

        # Update job metadata
        JobMetadata.update_detail_job(job_id, metadata, {:ok, result})

        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, result}

      {:error, reason} = error ->
        # Update job metadata with error information
        JobMetadata.update_error(job_id, reason, context: %{
          "venue_title" => venue_data["title"],
          "force_refresh_images" => force_refresh_images  # Include the flag in error context
        })

        Logger.error("❌ Failed to process venue: #{venue_data["title"]} - #{inspect(reason)}")
        error
    end
  end

  # Process venue - adapted from GeeksWhoDrink scraper
  # Add force_refresh_images parameter for explicit passing
  def process_venue(venue_data, source, force_refresh_images) do
    try do
      # Get additional details from venue page
      additional_details =
        case VenueDetailsExtractor.extract_additional_details(venue_data["source_url"]) do
          {:ok, details} -> details
          _ -> %{}
        end

      # Decode HTML entities from title
      clean_title = HtmlEntities.decode(venue_data["title"])

      # Parse day of week from time_text
      day_of_week = case venue_data["time_text"] do
        time_text when is_binary(time_text) and byte_size(time_text) > 3 ->
          case TimeParser.parse_day_of_week(time_text) do
            {:ok, day} -> day
            _ -> 2  # Default to Tuesday (2) if parsing fails
          end
        _ -> 2  # Default to Tuesday if time_text is invalid
      end

      # Merge venue data with additional details
      venue_data_map = %{
        raw_title: venue_data["title"],
        title: clean_title,
        address: venue_data["address"],
        time_text: venue_data["time_text"],
        url: venue_data["source_url"],
        hero_image_url: venue_data["logo_url"],
        day_of_week: day_of_week,  # Add day_of_week to the map
        frequency: :weekly,  # Add default frequency key
        start_time: Map.get(additional_details, :start_time)
      }

      # Merge with additional details
      merged_data = Map.merge(venue_data_map, additional_details)
      |> tap(&VenueHelpers.log_venue_details/1)

      # Prepare data for VenueStore
      latitude = venue_data["latitude"]
      longitude = venue_data["longitude"]
      has_coordinates = latitude && longitude && is_number(latitude) && is_number(longitude)

      venue_attrs = %{
        name: clean_title,
        address: merged_data.address,
        phone: Map.get(merged_data, :phone, nil),
        website: Map.get(merged_data, :website, nil),
        facebook: Map.get(merged_data, :facebook, nil),
        instagram: Map.get(merged_data, :instagram, nil),
        hero_image_url: Map.get(merged_data, :hero_image_url, nil)
      }

      # Only add coordinates if they exist and are valid
      venue_attrs = if has_coordinates do
        Logger.info("📍 Using coordinates directly from venue data: #{latitude}, #{longitude}")
        Map.merge(venue_attrs, %{latitude: latitude, longitude: longitude})
      else
        venue_attrs
      end

      Logger.info("""
      🏢 Processing venue through VenueStore:
        Name: #{venue_attrs.name}
        Address: #{venue_attrs.address}
        Website: #{venue_attrs.website}
      """)

      venue_result = VenueStore.process_venue(venue_attrs)

      # Unwrap venue result to ensure we never access tuple properties directly
      case venue_result do
        {:ok, venue} ->
          Logger.info("✅ Successfully processed venue: #{venue.name}")

          # Schedule a separate job for Google Place lookup
          schedule_place_lookup(venue)

          # Parse day and time
          time_text = format_event_time(venue_data_map, additional_details)

          # Get performer ID if present
          performer_id = get_performer_id(source.id, additional_details)

          # If force_refresh_images is true, clean existing images
          if force_refresh_images do
            clean_venue_hero_image(venue, day_of_week)
          end

          # Process hero image if present with force_refresh flag
          hero_image_attrs = if venue_data["logo_url"] && venue_data["logo_url"] != "" do
            # Explicitly pass the force_refresh flag to the downloader
            case ImageDownloader.download_event_hero_image(venue_data["logo_url"], force_refresh_images) do
              {:ok, upload} ->
                Logger.debug("🖼️ Downloaded hero image: #{inspect(upload, pretty: true)}")
                %{hero_image: upload, hero_image_url: venue_data["logo_url"]}
              {:error, reason} ->
                Logger.warning("⚠️ Failed to download hero image: #{inspect(reason)}")
                %{hero_image_url: venue_data["logo_url"]}
            end
          else
            %{}
          end

          # Create event data
          event_data = %{
            raw_title: "Geeks Who Drink at #{venue.name}",
            name: venue.name,
            time_text: time_text,
            description: Map.get(merged_data, :description, ""),
            fee_text: "Free", # Explicitly set as free for all GWD events
            source_url: venue_data["source_url"],
            performer_id: performer_id
          } |> Map.merge(hero_image_attrs)

          # Log inside this context to verify force_refresh_images value
          Logger.info("⚠️ Before creating event task, force_refresh=#{inspect(force_refresh_images)}")

          # CRITICAL: Use Task with explicit variable capture for force_refresh_images
          event_task = Task.async(fn ->
            # Log inside task to verify value was captured
            Logger.info("⚠️ TASK is using force_refresh=#{inspect(force_refresh_images)}")

            # Process the event and unwrap the result safely
            # Pass force_refresh_images explicitly to EventStore.process_event
            EventStore.process_event(venue, event_data, source.id, force_refresh_images: force_refresh_images)
          end)

          # Debug log to see exactly what the event_result contains
          event_result = Task.await(event_task)
          Logger.debug("🎭 EventStore.process_event result: #{inspect(event_result, pretty: true)}")

          # Double pattern match to handle nested tuples - THIS IS THE KEY FIX!
          # EventStore.process_event returns {:ok, {:ok, event}} because it's the result of a transaction
          case event_result do
            # First pattern: transaction succeeded with a successful database operation
            {:ok, {:ok, event}} ->
              Logger.info("✅ Successfully created event for venue: #{venue.name}")

              # Create final_data structure with all essential information for metadata
              final_data = %{
                "venue_id" => venue.id,
                "venue_name" => venue.name,
                "address" => venue_data["address"],
                "url" => venue_data["source_url"],
                "event_id" => event.id,
                "day_of_week" => event.day_of_week,
                "start_time" => event.start_time && Time.to_iso8601(event.start_time),
                "frequency" => event.frequency && to_string(event.frequency),
                "fee_text" => "Free",
                "time_text" => time_text,
                "source_name" => source.name,
                "force_refresh_images" => force_refresh_images  # Include the flag in the final data
              }

              # Add performer ID if available
              final_data = if performer_id do
                Map.put(final_data, "performer_id", performer_id)
              else
                final_data
              end

              # Return success with properly structured data
              {:ok, %{
                venue: venue,
                event: event,
                final_data: final_data
              }}

            # Other transaction success patterns with database errors
            {:ok, {:error, reason}} ->
              Logger.error("❌ Database error while creating event: #{inspect(reason)}")
              {:error, reason}

            # Transaction failed
            {:error, reason} ->
              Logger.error("❌ Transaction failed when creating event: #{inspect(reason)}")
              {:error, reason}

            # Unexpected result format - log a detailed warning
            unexpected ->
              Logger.warning("""
              ⚠️ Unexpected result format from EventStore.process_event
              Expected {:ok, {:ok, event}} but got: #{inspect(unexpected)}
              This might indicate a change in the EventStore.process_event return format
              """)
              {:error, "Unexpected result format from EventStore.process_event"}
          end

        {:error, reason} ->
          Logger.error("❌ Failed to process venue: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        # Special handling for tuple access errors
        error_message = Exception.message(e)

        if String.contains?(error_message, "key :id not found in: {:ok") do
          Logger.error("""
          ❌ Pattern matching error detected
          Error: #{error_message}
          This appears to be an issue with accessing a field on a tuple result.
          """)

          # Extract event ID from the error message
          event_id = case Regex.run(~r/id: (\d+),/, error_message) do
            [_, id] -> String.to_integer(id)
            _ -> nil
          end

          # Extract venue ID from the error message
          venue_id = case Regex.run(~r/venue_id: (\d+),/, error_message) do
            [_, id] -> String.to_integer(id)
            _ -> nil
          end

          # Extract performer ID from the error message if available
          performer_id = case Regex.run(~r/performer_id: (\d+),/, error_message) do
            [_, id] -> String.to_integer(id)
            _ -> nil
          end

          # Extract venue name if possible
          venue_name = case Regex.run(~r/name: "([^"]+)"/, error_message) do
            [_, name] -> name
            _ -> "Unknown"
          end

          if event_id && venue_id do
            Logger.info("✅ Extracted event ID #{event_id} and venue ID #{venue_id} from error message")

            # Simplified approach for error recovery
            final_data = %{
              "venue_id" => venue_id,
              "venue_name" => venue_name,
              "event_id" => event_id,
              "error_recovered" => true,
              "force_refresh_images" => force_refresh_images  # Include the flag in recovered data
            }

            # Add performer ID if available
            final_data = if performer_id do
              Map.put(final_data, "performer_id", performer_id)
            else
              final_data
            end

            # Return using consistent format
            {:ok, %{
              venue: %{id: venue_id, name: venue_name},
              event: %{id: event_id},
              final_data: final_data
            }}
          else
            {:error, "Failed to extract necessary IDs from error: #{error_message}"}
          end
        else
          Logger.error("❌ Failed to process venue: #{error_message}")
          {:error, error_message}
        end
    end
  end

  # Clean existing hero image when force_refresh_images is true
  defp clean_venue_hero_image(venue, day_of_week) do
    # Find existing event for this venue and day
    existing_event = find_existing_event(venue.id, day_of_week)

    if existing_event && existing_event.hero_image do
      Logger.info("🧨 Force refresh enabled - clearing hero image for event at venue: #{venue.name}")

      # Clear hero_image field in database
      try do
        existing_event
        |> Ecto.Changeset.change(%{hero_image: nil})
        |> Repo.update()
        |> case do
          {:ok, _updated} ->
            Logger.info("✅ Successfully cleared hero_image field for event ID: #{existing_event.id}")
          {:error, reason} ->
            Logger.error("❌ Failed to clear hero_image field: #{inspect(reason)}")
        end
      rescue
        e -> Logger.error("❌ Exception clearing hero_image: #{Exception.message(e)}")
      end
    else
      if existing_event do
        Logger.info("ℹ️ No existing hero image to clear for event ID: #{existing_event.id}")
      else
        Logger.info("ℹ️ No existing event found for venue: #{venue.name} on day #{day_of_week}")
      end
    end
  end

  # Find an existing event for a venue on a specific day
  defp find_existing_event(venue_id, day_of_week) do
    Repo.get_by(Event, venue_id: venue_id, day_of_week: day_of_week)
  end

  # Format event time - adapted from GeeksWhoDrink scraper
  defp format_event_time(venue_data, additional_details) do
    # Log inputs for debugging
    Logger.debug("""
    📅 Format Event Time:
      venue_data.time_text: #{inspect(venue_data.time_text)}
      venue_data.day_of_week: #{inspect(Map.get(venue_data, :day_of_week, nil))}
      additional_details.start_time: #{inspect(Map.get(additional_details, :start_time, nil))}
    """)

    # Use the day_of_week from venue_data that we've already parsed
    day_name = day_to_string(venue_data.day_of_week)

    # Extract time from additional details if available
    time = cond do
      # If start_time is available as a formatted string
      is_binary(Map.get(additional_details, :start_time, "")) &&
      String.match?(additional_details.start_time, ~r/\d{2}:\d{2}/) ->
        Logger.debug("📅 Using start_time from additional_details: #{additional_details.start_time}")
        additional_details.start_time

      # If we can extract time from the venue time_text
      is_binary(venue_data.time_text) and byte_size(venue_data.time_text) > 3 ->
        Logger.debug("📅 Attempting to parse time from venue_data.time_text: #{venue_data.time_text}")
        case TimeParser.parse_time(venue_data.time_text) do
          {:ok, time_str} ->
            Logger.debug("📅 Successfully parsed time: #{time_str}")
            time_str
          _ ->
            Logger.debug("📅 Failed to parse time, using default")
            "20:00"  # Default time
        end

      # Default fallback
      true ->
        Logger.debug("📅 No valid time source found, using default time")
        "20:00"
    end

    # Format: "Day HH:MM"
    formatted_time = "#{day_name} #{time}"
    Logger.debug("📅 Final formatted time: #{formatted_time}")
    formatted_time
  end

  defp day_to_string(day_of_week) do
    case day_of_week do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Tuesday" # Fallback
    end
  end

  defp get_performer_id(source_id, additional_details) do
    # Check if there's performer data in the additional details
    case Map.get(additional_details, :performer) do
      %{name: name, profile_image: image_url} when not is_nil(name) and not is_nil(image_url) ->
        Logger.info("🎭 Found performer: #{name} with image: #{image_url}")

        # Download the profile image using safe_download_performer_image
        case ImageDownloader.safe_download_performer_image(image_url) do
          {:ok, profile_image} when not is_nil(profile_image) ->
            Logger.info("📸 Successfully downloaded performer image for #{name}")

            # Create or update the performer
            performer_attrs = %{
              name: name,
              profile_image: profile_image,
              source_id: source_id
            }

            case Performer.find_or_create(performer_attrs) do
              {:ok, performer} ->
                Logger.info("✅ Created/updated performer: #{name}, ID: #{performer.id}")
                performer.id
              {:error, changeset} ->
                Logger.error("❌ Failed to create performer: #{inspect(changeset.errors)}")
                nil
            end

          {:ok, nil} ->
            Logger.warning("⚠️ Image download returned nil for performer #{name}, proceeding without image")

            # Try to create performer without image
            case Performer.find_or_create(%{
              name: name,
              source_id: source_id
            }) do
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

      _ ->
        Logger.debug("🔍 No performer data found in additional details")
        nil
    end
  end

  # Schedules a separate job for Google Place API lookups
  defp schedule_place_lookup(venue) do
    # Create a job with the venue ID
    %{"venue_id" => venue.id}
    |> GooglePlaceLookupJob.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info("📍 Scheduled Google Place lookup for venue: #{venue.name}")
      {:error, reason} ->
        Logger.warning("⚠️ Failed to schedule Google Place lookup: #{inspect(reason)}")
    end
  end
end

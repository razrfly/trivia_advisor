defmodule TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkDetailJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.VenueDetailsExtractor
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers, JobMetadata}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer}
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob
  alias HtmlEntities

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue" => venue_data, "source_id" => source_id}, id: job_id}) do
    Logger.info("🔄 Processing venue: #{venue_data["title"]}")
    source = Repo.get!(Source, source_id)

    # Process the venue and event using existing code patterns
    case process_venue(venue_data, source) do
      {:ok, %{venue: venue, event: event, final_data: final_data}} ->
        # Extract only the most relevant fields for metadata
        metadata = Map.take(final_data, [:name, :address, :day_of_week, :start_time, :performer_id])
          |> Map.put(:venue_id, venue.id)
          |> Map.put(:event_id, event.id)
          |> Map.put(:processed_at, DateTime.utc_now() |> DateTime.to_iso8601())

        # Convert atom keys to strings if needed
        result = {:ok, %{venue_id: venue.id, event_id: event.id}}
        JobMetadata.update_detail_job(job_id, metadata, result)

        Logger.info("✅ Successfully processed venue: #{venue.name}")
        result

      {:error, reason} = error ->
        # Update job metadata with error information
        JobMetadata.update_error(job_id, reason, context: %{
          "venue_title" => venue_data["title"]
        })

        Logger.error("❌ Failed to process venue: #{venue_data["title"]} - #{inspect(reason)}")
        error
    end
  end

  # Process venue - adapted from GeeksWhoDrink scraper
  def process_venue(venue_data, source) do
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
      venue_attrs = %{
        name: clean_title,
        address: merged_data.address,
        phone: Map.get(merged_data, :phone, nil),
        website: Map.get(merged_data, :website, nil),
        facebook: Map.get(merged_data, :facebook, nil),
        instagram: Map.get(merged_data, :instagram, nil),
        hero_image_url: Map.get(merged_data, :hero_image_url, nil)
      }

      Logger.info("""
      🏢 Processing venue through VenueStore:
        Name: #{venue_attrs.name}
        Address: #{venue_attrs.address}
        Website: #{venue_attrs.website}
      """)

      case VenueStore.process_venue(venue_attrs) do
        {:ok, venue} ->
          Logger.info("✅ Successfully processed venue: #{venue.name}")

          # Schedule Google Place lookup as a separate job
          schedule_place_lookup(venue)

          # Parse day and time
          time_text = format_event_time(venue_data_map, additional_details)

          # Get performer ID if present
          performer_id = get_performer_id(source.id, additional_details)

          # Process hero image if present
          hero_image_attrs = if venue_data["logo_url"] && venue_data["logo_url"] != "" do
            case ImageDownloader.download_event_hero_image(venue_data["logo_url"]) do
              {:ok, upload} ->
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

          case EventStore.process_event(venue, event_data, source.id) do
            {:ok, event} ->
              Logger.info("✅ Successfully created event for venue: #{venue.name}")

              # Create final_data structure for metadata
              final_data = merged_data
                |> Map.put(:venue_id, venue.id)
                |> Map.put(:venue_name, venue.name)
                |> Map.put(:event_id, event.id)
                |> Map.put(:performer_id, performer_id)

              {:ok, %{venue: venue, event: event, final_data: final_data}}

            {:error, reason} ->
              Logger.error("❌ Failed to create event: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("❌ Failed to process venue: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("""
        ❌ Failed to process venue
        Error: #{Exception.message(e)}
        Venue Data: #{inspect(venue_data)}
        """)
        {:error, "Exception: #{Exception.message(e)}"}
    end
  end

  # Schedule a Google Place lookup job
  defp schedule_place_lookup(venue) do
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
end

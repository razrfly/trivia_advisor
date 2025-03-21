defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    priority: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Quizmeisters.VenueExtractor
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers, JobMetadata, ImageDownloader}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer, Event}
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob

  # HTTP options
  @http_options [
    follow_redirect: true,
    timeout: 30_000,        # 30 seconds for connect timeout
    recv_timeout: 30_000,   # 30 seconds for receive timeout
    hackney: [pool: false]  # Don't use connection pooling for scrapers
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue" => venue_data, "source_id" => source_id}, id: job_id}) do
    Logger.info("🔄 Processing venue: #{venue_data["name"]}")

    # Get the source
    source = Repo.get!(Source, source_id)

    # Process the venue
    result = process_venue(venue_data, source, job_id)

    # Debug log the final result structure
    Logger.debug("📊 Result structure: #{inspect(result)}")

    # Standardize the result format
    handle_processing_result(result)
  end

  # Standardize the result format - similar to Question One's approach
  defp handle_processing_result(result) do
    case result do
      {:ok, venue} when is_map(venue) ->
        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, %{venue_id: venue.id}}

      {:ok, %{venue_id: venue_id, event_id: event_id}} ->
        Logger.info("✅ Successfully processed venue and event IDs: #{venue_id}, #{event_id}")
        {:ok, %{venue_id: venue_id, event_id: event_id}}

      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        {:error, reason}

      other ->
        Logger.error("❌ Unexpected result format: #{inspect(other)}")
        {:error, "Unexpected result format"}
    end
  end

  # Main processing function - similar to Question One's fetch_venue_details
  defp process_venue(location, source, job_id) do
    # Parse the time text from the venue data
    time_text = get_time_text(location)

    case TimeParser.parse_time_text(time_text) do
      {:ok, %{day_of_week: day_of_week, start_time: start_time}} ->
        # Fetch venue details from the venue page
        case fetch_venue_details(location, day_of_week, start_time, source, job_id) do
          {:ok, result} -> result
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} ->
        Logger.error("Failed to parse time text: #{reason} for #{location["name"]}")
        {:error, reason}
    end
  end

  # Get the time text, trying different sources in the venue data
  defp get_time_text(location) do
    # First try custom_fields
    time_text = case location do
      %{"custom_fields" => custom_fields} when is_map(custom_fields) ->
        case Map.get(custom_fields, "trivia_night") do
          value when is_binary(value) and byte_size(value) > 0 -> value
          _ -> ""
        end
      _ -> ""
    end

    # If still empty, try fields array
    time_text = if time_text == "" do
      case location do
        %{"fields" => fields} when is_list(fields) ->
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
        _ -> ""
      end
    else
      time_text
    end

    # If we still can't determine a day/time, use a default value
    if time_text == "" do
      Logger.warning("⚠️ No trivia day/time found for venue: #{location["name"]}. Using defaults.")
      "Thursday 7:00 PM" # Default to Thursday 7:00 PM
    else
      time_text
    end
  end

  # Fetch venue details from the venue page
  defp fetch_venue_details(location, day_of_week, start_time, source, job_id) do
    # Build the venue data for processing
    venue_data = %{
      raw_title: location["name"],
      title: location["name"],
      name: location["name"],
      address: location["address"],
      time_text: format_time_text(day_of_week, start_time),
      day_of_week: day_of_week,
      start_time: start_time,
      frequency: :weekly,
      fee_text: "Free", # All Quizmeisters events are free
      phone: location["phone"],
      url: location["url"],
      website: location["url"],
      latitude: location["lat"],
      longitude: location["lng"],
      postcode: location["postcode"],
      description: nil,
      hero_image_url: nil
    }

    # Log venue details for debugging
    VenueHelpers.log_venue_details(venue_data)

    # Fetch the venue page with timeout protection
    case HTTPoison.get(venue_data.url, [], @http_options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, document} <- Floki.parse_document(body),
             {:ok, extracted_data} <- VenueExtractor.extract_venue_data(document, venue_data.url, venue_data.raw_title) do

          # Merge extracted data with venue data
          merged_data = Map.merge(venue_data, extracted_data)

          # Process venue
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

          with {:ok, venue} <- VenueStore.process_venue(venue_store_data) do
            # Schedule Google Place lookup
            schedule_google_lookup(venue)

            # Process performer if present
            performer_id = process_performer(merged_data.performer, venue, source)

            # Process hero image
            hero_image_attrs = process_hero_image(merged_data.hero_image_url, venue.name)

            # Update existing event or create new one
            existing_event = find_existing_event(venue.id, merged_data.day_of_week)

            # Try to update existing event with performer
            if existing_event && performer_id do
              # Update existing event with performer
              case update_event_with_performer(existing_event, performer_id, venue) do
                {:ok, updated_event} ->
                  # Create metadata for reporting and update job
                  update_success_metadata(job_id, venue, updated_event, source)
                  {:ok, %{venue_id: venue.id, event_id: updated_event.id}}

                {:error, _reason} ->
                  # Fall back to normal event processing
                  create_and_process_event(venue, merged_data, performer_id, hero_image_attrs, source, job_id)
              end
            else
              # Create and process new event
              create_and_process_event(venue, merged_data, performer_id, hero_image_attrs, source, job_id)
            end
          else
            {:error, reason} ->
              Logger.error("❌ Failed to process venue: #{inspect(reason)}")
              {:error, reason}
          end
        else
          {:error, reason} ->
            Logger.error("❌ Failed to extract venue data: #{reason}")
            {:error, reason}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} when fetching venue: #{venue_data.url}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("Error fetching venue #{venue_data.url}: #{inspect(error)}")
        {:error, error}
    end
  end

  # Process hero image with the centralized ImageDownloader
  defp process_hero_image(hero_image_url, venue_name) do
    if hero_image_url && hero_image_url != "" do
      case ImageDownloader.download_event_hero_image(hero_image_url) do
        {:ok, upload} ->
          Logger.info("✅ Successfully downloaded hero image for #{venue_name}")
          %{"hero_image" => upload, "hero_image_url" => hero_image_url}
        {:error, reason} ->
          Logger.warning("⚠️ Failed to download hero image for #{venue_name}: #{inspect(reason)}")
          %{"hero_image_url" => hero_image_url}
      end
    else
      Logger.debug("ℹ️ No hero image URL provided for venue: #{venue_name}")
      %{}
    end
  end

  # Process performer data if available
  defp process_performer(performer_data, venue, source) do
    case performer_data do
      %{name: name, profile_image: image_url} when not is_nil(name) and is_binary(image_url) and image_url != "" ->
        Logger.info("🎭 Found performer data for #{venue.name}: #{name}")

        # Download performer image
        profile_image = ImageDownloader.download_performer_image(image_url)

        if profile_image do
          # Create or update performer
          performer_attrs = %{
            name: name,
            profile_image: profile_image,
            source_id: source.id
          }

          case Performer.find_or_create(performer_attrs) do
            {:ok, performer} ->
              Logger.info("✅ Created/updated performer: #{performer.name}")
              performer.id
            {:error, changeset} ->
              Logger.error("❌ Failed to create performer: #{inspect(changeset.errors)}")
              nil
          end
        else
          Logger.error("❌ Failed to download performer image")
          nil
        end
      _ ->
        Logger.info("ℹ️ No performer data found for #{venue.name}")
        nil
    end
  end

  # Create and process event with all necessary data
  defp create_and_process_event(venue, venue_data, performer_id, hero_image_attrs, source, job_id) do
    # Create event data with proper format
    event_data = %{
      "raw_title" => venue_data.raw_title,
      "name" => venue.name,
      "time_text" => format_time_text(venue_data.day_of_week, venue_data.start_time),
      "description" => venue_data.description,
      "fee_text" => "Free",
      "source_url" => venue_data.url,
      "performer_id" => performer_id
    } |> Map.merge(hero_image_attrs)

    # Process the event
    case EventStore.process_event(venue, event_data, source.id) do
      {:ok, event} when is_map(event) ->
        Logger.info("✅ Successfully processed event for venue: #{venue.name}")
        update_success_metadata(job_id, venue, event, source)
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      {:ok, {:ok, event}} when is_map(event) -> # Handle nested :ok tuples
        Logger.info("✅ Successfully processed event for venue: #{venue.name}")
        update_success_metadata(job_id, venue, event, source)
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      {:error, reason} ->
        Logger.error("❌ Failed to process event: #{inspect(reason)}")
        # Update metadata with error
        error_metadata = %{
          "venue_name" => venue.name,
          "venue_id" => venue.id,
          "error" => inspect(reason),
          "error_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        JobMetadata.update_detail_job(job_id, error_metadata, nil)
        {:error, reason}
    end
  end

  # Update existing event with performer ID
  defp update_event_with_performer(event, performer_id, _venue) do
    Logger.info("🔄 Updating existing event #{event.id} with performer_id #{performer_id}")

    event
    |> Ecto.Changeset.change(%{performer_id: performer_id})
    |> Repo.update()
    |> case do
      {:ok, _updated_event} = result ->
        Logger.info("✅ Updated existing event with performer_id")
        result
      error ->
        Logger.error("❌ Failed to update event with performer_id")
        error
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

  # Update job metadata with success info
  defp update_success_metadata(job_id, venue, event, source) do
    metadata = %{
      "venue_name" => venue.name,
      "venue_id" => venue.id,
      "event_id" => event.id,
      "address" => venue.address || "",
      "phone" => venue.phone || "",
      "source_name" => source.name,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    JobMetadata.update_detail_job(job_id, metadata, %{
      venue_id: venue.id,
      event_id: event.id
    })
  end

  # Schedule Google Place lookup job
  defp schedule_google_lookup(venue) do
    Logger.info("🔄 Scheduling Google Place lookup job for venue: #{venue.name}")

    %{"venue_id" => venue.id}
    |> GooglePlaceLookupJob.new()
    |> Oban.insert()
  end

  # Format time text for consistent display
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

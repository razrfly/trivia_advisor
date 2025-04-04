defmodule TriviaAdvisor.Events.EventStore do
  @moduledoc """
  Handles creating and updating events and their sources.
  """

  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Events.{Event, EventSource}
  require Logger

  # Import only the parse_currency function
  import Event, only: [parse_currency: 2]

  @doc """
  Process event data from a scraper, creating or updating the event and its source.
  If day_of_week changes, creates a new event instead of updating.

  Parameters:
  - venue: The venue struct associated with the event
  - event_data: Map containing event attributes
  - source_id: The ID of the source platform
  - opts: Optional keyword list containing:
    - force_refresh_images: true/false (default false) - When true, will force re-download of images
  """
  def process_event(venue, event_data, source_id, opts \\ []) do
    # Ensure upload directory exists
    ensure_upload_dir()

    # Set force_refresh_images in process dictionary if passed in opts
    force_refresh_images = Keyword.get(opts, :force_refresh_images, false)
    # Log the force_refresh_images flag value for debugging
    Logger.info("🔄 Force refresh flag: #{inspect(force_refresh_images)}")

    if force_refresh_images do
      # CRITICAL FIX: Don't set this to true if not specified in opts
      # This was replacing any previous value with true
      Process.put(:force_refresh_images, true)
      Logger.info("⚠️ Force image refresh enabled in EventStore")
    end

    # No else branch - we only set true, never set false
    # This lets values cascade down from the parent job

    # Convert string keys to atoms for consistent access
    # This allows the function to work with both string and atom keys
    event_data = normalize_keys(event_data)

    # Log the performer_id from event_data
    Logger.info("🎭 Processing event for venue #{venue.name} with performer_id: #{inspect(Map.get(event_data, :performer_id))}")

    # Preload required associations
    venue = Repo.preload(venue, [city: :country])

    # Parse frequency from the raw title
    frequency = parse_event_frequency(event_data.raw_title)

    # Download and attach hero image if URL is present
    hero_image_attrs = case event_data.hero_image_url do
      url when is_binary(url) and url != "" ->
        case download_hero_image(url) do
          {:ok, upload} ->
            try do
              # Test if Waffle can process the image by checking file validity
              extension = Path.extname(upload.filename) |> String.downcase()

              # Check if image has valid extension, if not use the one we detected
              if extension == "" or not Regex.match?(~r/\.(jpg|jpeg|png|gif|webp)$/i, extension) do
                Logger.debug("Using detected extension for image without extension")
                # Get the detected extension from the content_type
                detected_ext = case upload.content_type do
                  "image/jpeg" -> ".jpg"
                  "image/png" -> ".png"
                  "image/gif" -> ".gif"
                  "image/webp" -> ".webp"
                  _ -> ".jpg" # Default to jpg
                end

                # Create a new upload struct with the filename + detected extension
                # But first check if the filename already ends with the correct extension to avoid duplication
                root_name = Path.rootname(upload.filename)
                filename_without_query = root_name |> String.split("?") |> List.first()

                # Re-normalize the filename to ensure consistent format between S3 and database
                alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
                normalized_filename = ImageDownloader.normalize_filename(filename_without_query)

                # Only add extension if the filename doesn't already end with it
                new_filename = if String.ends_with?(String.downcase(normalized_filename), detected_ext) do
                  normalized_filename
                else
                  normalized_filename <> detected_ext
                end

                # Create the new Plug.Upload struct with the corrected filename
                new_upload = %Plug.Upload{
                  path: upload.path,
                  filename: new_filename,
                  content_type: upload.content_type
                }
                %{hero_image: new_upload, hero_image_url: url}
              else
                # Original filename has valid extension
                %{hero_image: upload, hero_image_url: url}
              end
            rescue
              err ->
                Logger.error("Error processing hero image: #{inspect(err)}")
                %{hero_image_url: url}
            end
          {:error, reason} ->
            Logger.warning("Failed to download hero image: #{inspect(reason)}")
            %{hero_image_url: url}
        end
      _ -> %{}
    end

    # Get performer_id from event_data, ensuring it's properly passed through
    performer_id = Map.get(event_data, :performer_id)
    Logger.info("🎭 Using performer_id: #{inspect(performer_id)} for event at venue: #{venue.name}")

    attrs = %{
      name: event_data.raw_title,  # Keep the raw title
      venue_id: venue.id,
      day_of_week: parse_day_of_week(event_data.time_text),
      start_time: parse_time(event_data.time_text),
      frequency: frequency,
      entry_fee_cents: parse_currency(event_data.fee_text, venue) || 0,  # Always default to 0 if nil
      description: event_data.description,
      performer_id: performer_id  # Use the extracted performer_id
    }
    |> Map.merge(hero_image_attrs)  # Merge in hero image if downloaded

    Logger.debug("🎭 Event attributes: #{inspect(attrs)}")

    Repo.transaction(fn ->
      # First try to find by venue and day
      existing_event = find_existing_event(attrs.venue_id, attrs.day_of_week)

      # Log the existing event if found
      if existing_event do
        Logger.info("🔄 Found existing event #{existing_event.id} for venue #{venue.name} on day #{attrs.day_of_week}")
        Logger.info("🎭 Existing event has performer_id: #{inspect(existing_event.performer_id)}")

        # CRITICAL FIX: If force_refresh_images is true and event has a hero_image,
        # explicitly delete both new and legacy files BEFORE creating the new one
        if force_refresh_images && existing_event.hero_image do
          Logger.info("🧹 Force refresh: Explicitly deleting ALL hero image files for #{existing_event.name}")

          # Use explicit aliases for clarity
          alias TriviaAdvisor.Uploaders.HeroImage

          # 1. First use Waffle's standard delete to remove the current naming pattern files
          hero_image = existing_event.hero_image
          filename = hero_image.file_name

          # Call the delete function directly to remove both normal and legacy files
          Logger.info("🧹 Deleting hero image: #{filename} for event #{existing_event.id}")
          HeroImage.delete({filename, existing_event})
          Logger.info("✅ Hero image deletion completed")
        end
      else
        Logger.info("🆕 Creating new event for venue #{venue.name} on day #{attrs.day_of_week}")
      end

      # Include hero_image_url in the attrs for event_changed? check
      attrs_with_url = Map.put(attrs, :hero_image_url, event_data.hero_image_url)

      # Process the event
      result = case existing_event do
        nil -> create_event(attrs)
        event ->
          if event_changed?(event, attrs_with_url) do
            # Check if performer_id is changing
            if event.performer_id != attrs.performer_id do
              Logger.info("🎭 Updating performer_id from #{inspect(event.performer_id)} to #{inspect(attrs.performer_id)}")
            end
            update_event(event, attrs)
          else
            # If no changes, but performer_id is different, update just that field
            if not is_nil(attrs.performer_id) and event.performer_id != attrs.performer_id do
              Logger.info("🎭 Event not changed but performer_id is different. Updating just performer_id from #{inspect(event.performer_id)} to #{inspect(attrs.performer_id)}")
              event
              |> Ecto.Changeset.change(%{performer_id: attrs.performer_id})
              |> Repo.update()
            else
              {:ok, event}
            end
          end
      end

      case result do
        {:ok, event} ->
          # Log the result
          Logger.info("✅ Event processed successfully with ID: #{event.id}, performer_id: #{inspect(event.performer_id)}")

          # Pass all needed data to upsert_event_source
          case upsert_event_source(
            event.id,
            source_id,
            event_data.source_url,
            %{event_data: event_data, attrs: attrs, venue: venue, frequency: frequency}
          ) do
            {:ok, _source} -> {:ok, event}
            {:error, reason} ->
              Logger.error("Failed to upsert event source: #{inspect(reason)}")
              Repo.rollback(reason)
          end

        {:error, changeset} ->
          Logger.error("❌ Failed to process event: #{inspect(changeset.errors)}")

          # If the failure was specifically due to hero_image, try again without it
          if hero_image_error?(changeset) do
            Logger.warning("Retrying event creation without hero image due to validation error")
            # Remove hero_image from attrs and try again
            filtered_attrs = Map.drop(attrs, [:hero_image])
            case existing_event do
              nil -> create_event(filtered_attrs)
              event ->
                if event_changed?(event, filtered_attrs) do
                  update_event(event, filtered_attrs)
                else
                  {:ok, event}
                end
            end
            |> case do
              {:ok, event} ->
                # Pass all needed data to upsert_event_source
                case upsert_event_source(
                  event.id,
                  source_id,
                  event_data.source_url,
                  %{event_data: event_data, attrs: filtered_attrs, venue: venue, frequency: frequency}
                ) do
                  {:ok, _source} -> {:ok, event}
                  {:error, reason} -> Repo.rollback(reason)
                end
              {:error, reason} -> Repo.rollback(reason)
            end
          else
            Repo.rollback(changeset)
          end
      end
    end)
  end

  # Normalize keys to atoms for consistent access
  # This allows the function to work with both string and atom keys
  # Uses String.to_existing_atom first to prevent atom exhaustion risk
  defp normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      atom_key = if is_binary(k) do
        try do
          String.to_existing_atom(k)
        rescue
          ArgumentError -> String.to_atom(k)  # Fallback when atom doesn't exist
        end
      else
        k
      end
      Map.put(acc, atom_key, v)
    end)
  end

  defp find_existing_event(venue_id, day_of_week) do
    Repo.one(
      from e in Event,
      where: e.venue_id == ^venue_id and
             e.day_of_week == ^day_of_week,
      limit: 1
    )
  end

  defp create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  defp update_event(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  defp upsert_event_source(event_id, source_id, source_url, data) do
    now = DateTime.utc_now()
    Logger.info("🕒 Updating event_source last_seen_at to #{DateTime.to_string(now)}")
    Logger.info("🔗 Event ID: #{event_id}, Source ID: #{source_id}, Source URL: #{source_url}")

    # Build metadata from event data
    metadata = %{
      raw_title: data.event_data.raw_title,
      clean_title: data.event_data.name,
      address: data.venue.address,
      time_text: data.event_data.time_text,
      day_of_week: data.attrs.day_of_week,
      start_time: data.attrs.start_time,
      frequency: data.frequency,
      fee_text: data.event_data.fee_text,
      phone: data.venue.phone,
      website: data.venue.website,
      description: data.event_data.description,
      hero_image_url: data.event_data.hero_image_url
    }

    case Repo.get_by(EventSource, event_id: event_id, source_id: source_id) do
      nil ->
        Logger.info("🆕 Creating new event_source for event_id #{event_id}, source_id #{source_id}")
        %EventSource{}
        |> EventSource.changeset(%{
          event_id: event_id,
          source_id: source_id,
          source_url: source_url,
          metadata: metadata,
          last_seen_at: now
        })
        |> Repo.insert()
        |> case do
          {:ok, event_source} ->
            Logger.info("✅ Successfully created new event_source #{event_source.id} with last_seen_at: #{DateTime.to_string(event_source.last_seen_at)}")
            {:ok, event_source}
          {:error, changeset} ->
            Logger.error("❌ Failed to create event_source: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      source ->
        Logger.info("🔄 Updating existing event_source #{source.id} with last_seen_at: #{DateTime.to_string(now)}")
        Logger.info("🔍 Existing source_url: #{source.source_url}")
        Logger.info("🔍 New source_url: #{source_url}")

        source
        |> EventSource.changeset(%{
          source_url: source_url,
          metadata: metadata,
          last_seen_at: now
        })
        |> Repo.update()
        |> case do
          {:ok, updated_source} ->
            Logger.info("✅ Successfully updated event_source #{updated_source.id} with last_seen_at: #{DateTime.to_string(updated_source.last_seen_at)}")
            {:ok, updated_source}
          {:error, changeset} ->
            Logger.error("❌ Failed to update event_source: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  # Check if event has changed in a way that requires an update
  # Note: We're not including performer_id here because we want to update it separately
  # if it's the only thing that changed
  defp event_changed?(event, attrs) do
    # Get force_refresh_images from process dictionary
    force_refresh_images = Process.get(:force_refresh_images, false)

    # Get the event source to access hero_image_url from metadata
    event_source = Repo.get_by(EventSource, event_id: event.id)
    current_hero_image_url = if event_source, do: get_in(event_source.metadata, ["hero_image_url"]), else: nil

    # New hero_image_url from attrs
    new_hero_image_url = attrs[:hero_image_url]

    # Check if event has a hero_image but the actual file might be missing
    # This could happen if the file was deleted during force_refresh_images
    image_potentially_missing = force_refresh_images && event.hero_image && new_hero_image_url

    # Compare basic fields
    basic_fields_changed = Map.take(event, [:start_time, :frequency, :entry_fee_cents, :description]) !=
                         Map.take(attrs, [:start_time, :frequency, :entry_fee_cents, :description])

    # Check if hero_image_url changed (using our safer implementation)
    hero_image_changed = hero_image_changed?(current_hero_image_url, new_hero_image_url)

    # Check if we should force update due to force_refresh_images
    force_image_update = force_refresh_images &&
                        (!is_nil(new_hero_image_url) || !is_nil(current_hero_image_url))

    if force_image_update do
      Logger.info("⚠️ Force updating event due to force_refresh_images=#{force_refresh_images}")
    end

    # Log the comparison for debugging
    Logger.info("🔍 Hero image comparison - Current: #{inspect(current_hero_image_url)}, New: #{inspect(new_hero_image_url)}, Changed: #{hero_image_changed}, Force update: #{force_image_update}, Image potentially missing: #{image_potentially_missing}")

    # Event changed if either basic fields changed, hero image changed, image is potentially missing, or force update is enabled
    basic_fields_changed || hero_image_changed || force_image_update || image_potentially_missing
  end

  defp parse_day_of_week("Monday" <> _), do: 1
  defp parse_day_of_week("Tuesday" <> _), do: 2
  defp parse_day_of_week("Wednesday" <> _), do: 3
  defp parse_day_of_week("Thursday" <> _), do: 4
  defp parse_day_of_week("Friday" <> _), do: 5
  defp parse_day_of_week("Saturday" <> _), do: 6
  defp parse_day_of_week("Sunday" <> _), do: 7

  defp parse_time(time_text) do
    # Extract time from format like "Wednesday 20:00"
    case Regex.run(~r/\d{2}:\d{2}/, time_text) do
      [time] -> Time.from_iso8601!(time <> ":00")
      nil -> raise "Invalid time format: #{time_text}"
    end
  end

  # Parse frequency from event title
  defp parse_event_frequency(title) do
    title = String.downcase(title)
    cond do
      # Check for explicit monthly patterns with ordinals
      (String.contains?(title, ["first", "second", "third", "fourth", "last"]) and
       String.contains?(title, ["of the month", "of every month"])) or
      String.contains?(title, ["monthly"]) ->
        :monthly

      # Check for biweekly/fortnightly patterns
      String.contains?(title, ["every other", "bi-weekly", "biweekly", "fortnightly"]) ->
        :biweekly

      # Everything else is weekly (default for pub quizzes)
      true ->
        :weekly
    end
  end

  # Check if the changeset error is specifically related to the hero_image
  defp hero_image_error?(changeset) do
    Enum.any?(changeset.errors, fn {field, _} -> field == :hero_image end)
  end

  # Download hero image from URL
  defp download_hero_image(url) do
    # Use the centralized ImageDownloader to ensure consistent filename handling
    alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

    # CRITICAL FIX: Get force_refresh_images from process dictionary instead of hardcoding to true
    force_refresh_images = Process.get(:force_refresh_images, false)

    # Log for debugging
    Logger.info("🔄 EventStore.download_hero_image using force_refresh_images: #{inspect(force_refresh_images)}")

    # Pass the force_refresh_images flag from process dictionary
    ImageDownloader.download_event_hero_image(url, force_refresh_images)
  end

  # Ensure the upload directory exists
  defp ensure_upload_dir do
    dir = Path.join(["priv", "static", "uploads", "events"])
    File.mkdir_p!(dir)
  end

  # Improved hero_image check function that safely handles nil values
  defp hero_image_changed?(current_hero_image_url, new_hero_image_url) do
    # Early return for nil checks
    cond do
      # If both are nil, no change
      is_nil(current_hero_image_url) and is_nil(new_hero_image_url) ->
        false

      # If current is nil but new is not, it's a change
      is_nil(current_hero_image_url) and not is_nil(new_hero_image_url) ->
        # Ensure new is not empty
        new_hero_image_url = to_string(new_hero_image_url)
        String.trim(new_hero_image_url) != ""

      # If new is nil but current is not, it's a change
      not is_nil(current_hero_image_url) and is_nil(new_hero_image_url) ->
        true

      # If both exist, compare them properly
      true ->
        # Convert to string and trim
        current_str = to_string(current_hero_image_url) |> String.trim()
        new_str = to_string(new_hero_image_url) |> String.trim()

        # Compare the cleaned strings
        current_str != new_str && new_str != ""
    end
  end
end

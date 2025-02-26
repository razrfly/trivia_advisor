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
  """
  def process_event(venue, event_data, source_id) do
    # Ensure upload directory exists
    ensure_upload_dir()

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
                new_filename = upload.filename <> detected_ext
                new_upload = %Plug.Upload{
                  path: upload.path,
                  filename: new_filename,
                  content_type: upload.content_type
                }
                %{hero_image: new_upload}
              else
                # Original filename has valid extension
                %{hero_image: upload}
              end
            rescue
              err ->
                Logger.error("Error processing hero image: #{inspect(err)}")
                %{}
            end
          {:error, reason} ->
            Logger.warning("Failed to download hero image: #{inspect(reason)}")
            %{}
        end
      _ -> %{}
    end

    attrs = %{
      name: event_data.raw_title,  # Keep the raw title
      venue_id: venue.id,
      day_of_week: parse_day_of_week(event_data.time_text),
      start_time: parse_time(event_data.time_text),
      frequency: frequency,
      entry_fee_cents: parse_currency(event_data.fee_text, venue),
      description: event_data.description,
      performer_id: event_data.performer_id
    }
    |> Map.merge(hero_image_attrs)  # Merge in hero image if downloaded

    Repo.transaction(fn ->
      # First try to find by venue and day
      existing_event = find_existing_event(attrs.venue_id, attrs.day_of_week)

      # Process the event
      result = case existing_event do
        nil -> create_event(attrs)
        event ->
          if event_changed?(event, attrs) do
            update_event(event, attrs)
          else
            {:ok, event}
          end
      end

      case result do
        {:ok, event} ->
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
        %EventSource{}
        |> EventSource.changeset(%{
          event_id: event_id,
          source_id: source_id,
          source_url: source_url,
          metadata: metadata,
          last_seen_at: now
        })
        |> Repo.insert()

      source ->
        source
        |> EventSource.changeset(%{
          source_url: source_url,
          metadata: metadata,
          last_seen_at: now
        })
        |> Repo.update()
    end
  end

  defp event_changed?(event, attrs) do
    Map.take(event, [:start_time, :frequency, :entry_fee_cents, :description]) !=
    Map.take(attrs, [:start_time, :frequency, :entry_fee_cents, :description])
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

  # Download image to temp file and return path
  defp download_hero_image(url) do
    Logger.debug("Attempting to download hero image from URL: #{url}")

    # Add browser-like headers to avoid potential restrictions
    headers = [
      {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36"},
      {"Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9"}
    ]

    # Set reasonable timeout
    options = [follow_redirect: true, recv_timeout: 30000]

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        # Get existing filename and extension from URL
        filename = Path.basename(url)
        existing_extension = Path.extname(filename) |> String.downcase()

        # Detect content type and extension based on file content
        {content_type, extension} = detect_image_type(body, existing_extension)
        Logger.debug("Detected content type: #{content_type}, using extension: #{extension}")

        # Create temp file with proper extension
        temp_path = Path.join(
          System.tmp_dir!(),
          "hero_image_#{:crypto.strong_rand_bytes(16) |> Base.encode16}#{extension}"
        )

        with :ok <- File.write(temp_path, body) do
          Logger.debug("Successfully wrote image to: #{temp_path}")

          # Create a proper %Plug.Upload{} struct that Waffle expects
          # Important: Use original filename as-is
          {:ok, %Plug.Upload{
            path: temp_path,
            filename: filename,
            content_type: content_type
          }}
        else
          error ->
            Logger.error("Failed to write image file: #{inspect(error)}")
            {:error, :file_write_failed}
        end
      {:ok, response} ->
        Logger.error("Failed to download image, status code: #{response.status_code}")
        Logger.debug("Response headers: #{inspect(response.headers)}")
        {:error, :download_failed}
      {:error, reason} ->
        Logger.error("Failed to download image: #{inspect(reason)}")
        {:error, :download_failed}
    end
  end

  # Detect image type from binary content
  defp detect_image_type(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>, _) do
    {"image/png", ".png"}
  end
  defp detect_image_type(<<0xFF, 0xD8, 0xFF, _::binary>>, _) do
    {"image/jpeg", ".jpg"}
  end
  defp detect_image_type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>, _) do
    {"image/webp", ".webp"}
  end
  defp detect_image_type(<<0x47, 0x49, 0x46, 0x38, _::binary>>, _) do
    {"image/gif", ".gif"}
  end
  defp detect_image_type(_, ext) when ext in [".jpg", ".jpeg"] do
    {"image/jpeg", ext}
  end
  defp detect_image_type(_, ext) when ext in [".png"] do
    {"image/png", ext}
  end
  defp detect_image_type(_, ext) when ext in [".webp"] do
    {"image/webp", ext}
  end
  defp detect_image_type(_, ext) when ext in [".gif"] do
    {"image/gif", ext}
  end
  defp detect_image_type(_, _) do
    # Default to JPEG if we can't detect the type
    {"image/jpeg", ".jpg"}
  end

  # Make sure the directory exists
  defp ensure_upload_dir do
    Path.join([Application.app_dir(:trivia_advisor), "priv", "static", "uploads", "venues"])
    |> File.mkdir_p!()
  end

  # Check if changeset has errors related to hero_image
  defp hero_image_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:hero_image, _} -> true
      _ -> false
    end)
  end
end

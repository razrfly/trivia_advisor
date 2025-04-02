defmodule TriviaAdvisor.Scraping.Oban.QuestionOneDetailJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.QuestionOne.VenueExtractor
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Events.Event
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    # Log concise version of args
    Logger.info("🔄 Processing Question One detail job with args: #{inspect(Map.take(args, ["url", "title", "force_refresh_images"]))}")

    url = Map.get(args, "url")
    title = Map.get(args, "title")
    source_id = Map.get(args, "source_id")

    # Extract force_refresh_images flag
    force_refresh_images = Map.get(args, "force_refresh_images", false)

    # CRITICAL: Set the flag explicitly to true if it's true in the args
    if force_refresh_images do
      Logger.info("⚠️ Force image refresh enabled - will refresh ALL images regardless of existing state")
      Process.put(:force_refresh_images, true)
    else
      Process.put(:force_refresh_images, false)
    end

    # Log the value for verification
    Logger.info("📝 Force refresh images flag set to: #{inspect(Process.get(:force_refresh_images))}")

    # Get the Question One source
    source = Repo.get!(Source, source_id)

    # Store force_refresh_images in args to pass to fetch_venue_details
    fetch_args = %{
      url: url,
      title: title,
      force_refresh_images: Process.get(:force_refresh_images, false)
    }

    # Process the venue using the existing logic
    result = fetch_venue_details(fetch_args, source, job_id)

    # Handle the result with better pattern matching
    handle_processing_result(result)
  end

  # A catch-all handler that logs the structure and converts to a standardized format
  defp handle_processing_result(result) do
    case result do
      {:ok, venue} when is_struct(venue, TriviaAdvisor.Locations.Venue) ->
        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, %{venue_id: venue.id}}

      # Handle errors
      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        {:error, reason}

      # Catch-all for unexpected formats or nil results
      other ->
        Logger.error("❌ Unexpected result format or nil result: #{inspect(other)}")
        {:error, "Unexpected result format or nil result"}
    end
  end

  # The following functions are adapted from the Question One scraper
  # to avoid modifying the original code

  # Process a venue and create an event - adapted from QuestionOne.fetch_venue_details
  defp fetch_venue_details(%{url: url, title: raw_title, force_refresh_images: force_refresh_images}, source, job_id) do
    Logger.info("🔍 Processing venue: #{raw_title} with force_refresh_images=#{inspect(force_refresh_images)}")

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, document} <- Floki.parse_document(body),
             {:ok, extracted_data} <- VenueExtractor.extract_venue_data(document, url, raw_title),
             true <- String.length(extracted_data.title) > 0 || {:error, :empty_title},
             true <- String.length(extracted_data.address) > 0 || {:error, :empty_address} do

          # First process the venue
          venue_data = %{
            name: extracted_data.title,
            address: extracted_data.address,
            phone: extracted_data.phone,
            website: extracted_data.website
          }

          with {:ok, venue} <- VenueStore.process_venue(venue_data) do
            # Schedule a separate job for Google Place lookup
            Logger.info("🔄 Scheduling Google Place lookup job for venue: #{venue.name}")
            schedule_place_lookup(venue)

            # Delete any existing hero images if force_refresh_images is true
            if force_refresh_images do
              # Get venue slug for directory path
              venue_slug = venue.slug

              # Log the operation
              Logger.info("🧨 Force refresh enabled - cleaning venue images directory for #{venue.name}")

              # Construct the directory path
              venue_images_dir = Path.join(["priv/static/uploads/venues", venue_slug])

              # Check if directory exists before attempting to clean it
              if File.exists?(venue_images_dir) do
                # Get a list of image files in the directory
                case File.ls(venue_images_dir) do
                  {:ok, files} ->
                    image_extensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"]

                    # Filter to only include image files
                    image_files = Enum.filter(files, fn file ->
                      ext = Path.extname(file) |> String.downcase()
                      Enum.member?(image_extensions, ext)
                    end)

                    # Delete each image file
                    Enum.each(image_files, fn image_file ->
                      file_path = Path.join(venue_images_dir, image_file)
                      Logger.info("🗑️ Deleting image file: #{file_path}")

                      case File.rm(file_path) do
                        :ok ->
                          Logger.info("✅ Successfully deleted image file: #{file_path}")
                        {:error, reason} ->
                          Logger.error("❌ Failed to delete image file: #{file_path} - #{inspect(reason)}")
                      end
                    end)

                    # Log summary
                    Logger.info("🧹 Cleaned #{length(image_files)} image files from #{venue_images_dir}")

                    # If there is an existing event, also clear the hero_image field in the database
                    existing_event = find_existing_event(venue.id, extracted_data.day_of_week)
                    if existing_event && existing_event.hero_image do
                      Logger.info("🗑️ Clearing hero_image field for existing event #{existing_event.id}")

                      {:ok, _updated_event} =
                        existing_event
                        |> Ecto.Changeset.change(%{hero_image: nil})
                        |> Repo.update()

                      Logger.info("🧼 Cleared hero_image field on event #{existing_event.id}")
                    end
                  {:error, reason} ->
                    Logger.error("❌ Failed to list files in directory #{venue_images_dir}: #{inspect(reason)}")
                end
              else
                Logger.info("⚠️ No existing venue images directory found at #{venue_images_dir}")
              end
            end

            # Process the hero image using the centralized ImageDownloader
            hero_image_attrs = if extracted_data.hero_image_url && extracted_data.hero_image_url != "" do
              # Use the explicitly passed parameter
              Logger.info("🖼️ Processing hero image with force_refresh=#{inspect(force_refresh_images)}")

              case ImageDownloader.download_event_hero_image(extracted_data.hero_image_url, force_refresh_images) do
                {:ok, upload} ->
                  Logger.info("✅ Successfully downloaded hero image for #{venue.name}")

                  # Log where the final image will be saved
                  filename = upload.filename
                  if venue && venue.slug do
                    path = Path.join(["priv/static/uploads/venues", venue.slug, filename])
                    Logger.info("🔄 Image will be saved to final path: #{path}")
                  end

                  %{hero_image: upload, hero_image_url: extracted_data.hero_image_url}
                {:error, reason} ->
                  Logger.warning("⚠️ Failed to download hero image for #{venue.name}: #{inspect(reason)}")
                  %{hero_image_url: extracted_data.hero_image_url}
              end
            else
              Logger.debug("ℹ️ No hero image URL provided for venue: #{venue.name}")
              %{}
            end

            # Then process the event with the venue
            event_data = %{
              raw_title: raw_title,
              name: venue.name,
              time_text: extracted_data.time_text,
              description: extracted_data.description,
              fee_text: extracted_data.fee_text,
              source_url: url
            } |> Map.merge(hero_image_attrs)  # Merge the hero_image if we have it

            # Create a task that explicitly captures force_refresh_images variable
            Logger.info("⬆️ Creating Task with force_refresh_images=#{inspect(force_refresh_images)}")

            event_task = Task.async(fn ->
              # Log inside task to verify we're using the captured variable
              Logger.info("⚠️ TASK is using force_refresh=#{inspect(force_refresh_images)}")

              # Pass force_refresh_images explicitly as a keyword argument
              EventStore.process_event(venue, event_data, source.id, force_refresh_images: force_refresh_images)
            end)

            # Use a generous timeout for event processing
            case Task.yield(event_task, 45_000) || Task.shutdown(event_task) do
              {:ok, {:ok, {:ok, event}}} ->
                Logger.info("✅ Successfully processed event for venue: #{venue.name}")

                # Log the saved hero image with real path if it exists
                if event.hero_image && event.hero_image.file_name do
                  filename = event.hero_image.file_name
                  venue_slug = venue.slug
                  path = Path.join(["priv/static/uploads/venues", venue_slug, filename])

                  Logger.info("✅ Saved new hero image to: #{path}")
                end

                # Create metadata for reporting
                metadata = %{
                  "venue_name" => venue.name,
                  "venue_id" => venue.id,
                  "venue_url" => url,
                  "event_id" => event.id,
                  "source_id" => source.id,
                  "address" => venue.address,
                  "phone" => venue.phone || "",
                  "description" => extracted_data.description || "",
                  "source_name" => source.name,
                  "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
                  "time_text" => extracted_data.time_text || "",
                  "fee_text" => extracted_data.fee_text || ""
                }

                # Update job metadata
                JobMetadata.update_detail_job(job_id, metadata, {:ok, %{
                  venue_id: venue.id,
                  event_id: event.id
                }}, source_id: source.id)

                {:ok, venue}

              {:ok, {:ok, event}} when is_map(event) ->
                Logger.info("✅ Successfully processed event for venue: #{venue.name}")

                # Log the saved hero image with real path if it exists
                if event.hero_image && event.hero_image.file_name do
                  filename = event.hero_image.file_name
                  venue_slug = venue.slug
                  path = Path.join(["priv/static/uploads/venues", venue_slug, filename])

                  Logger.info("✅ Saved new hero image to: #{path}")
                end

                # Create metadata
                metadata = %{
                  "venue_name" => venue.name,
                  "venue_id" => venue.id,
                  "venue_url" => url,
                  "event_id" => event.id,
                  "source_id" => source.id,
                  "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                }

                JobMetadata.update_detail_job(job_id, metadata, {:ok, %{
                  venue_id: venue.id,
                  event_id: event.id
                }}, source_id: source.id)

                {:ok, venue}

              {:ok, {:error, reason}} ->
                Logger.error("❌ Failed to process event: #{inspect(reason)}")
                {:error, reason}

              nil ->
                Logger.error("⏱️ Timeout in EventStore.process_event for venue #{venue.name}")
                {:error, "EventStore.process_event timeout"}
            end
          else
            {:error, reason} ->
              Logger.error("❌ Failed to process venue: #{inspect(reason)}")
              {:error, reason}
          end
        else
          {:ok, %{title: _title} = data} ->
            Logger.error("❌ Missing required address in extracted data: #{inspect(data)}")
            {:error, :missing_address}
          {:error, :empty_title} ->
            Logger.error("❌ Empty title for venue: #{raw_title}")
            {:error, :empty_title}
          {:error, :empty_address} ->
            Logger.error("❌ Empty address for venue: #{raw_title}")
            {:error, :empty_address}
          error ->
            Logger.error("""
            ❌ Failed to process venue: #{raw_title}
            Reason: #{inspect(error)}
            URL: #{url}
            """)
            {:error, error}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching venue: #{url}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("❌ Error fetching venue #{url}: #{inspect(error)}")
        {:error, error}
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

  # Schedules a separate job for Google Place API lookups
  defp schedule_place_lookup(venue) do
    # Create a job with the venue ID
    %{"venue_id" => venue.id}
    |> GooglePlaceLookupJob.new()
    |> Oban.insert()
  end
end

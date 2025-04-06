defmodule TriviaAdvisor.Scraping.Oban.PubquizDetailJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata

  # Polish to numeric day mapping (0-6, where 0 is Sunday)
  @polish_days %{
    "PONIEDZIAŁEK" => 1,
    "WTOREK" => 2,
    "ŚRODA" => 3,
    "CZWARTEK" => 4,
    "PIĄTEK" => 5,
    "SOBOTA" => 6,
    "NIEDZIELA" => 0
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_data" => venue_data, "source_id" => source_id} = args, id: job_id}) do
    Logger.info("🔄 Processing venue: #{venue_data["name"]}")
    Logger.info("🔍 DETAIL JOB VENUE DATA: #{inspect(venue_data)}")

    # Extract force_refresh_images flag
    force_refresh_images = Map.get(args, "force_refresh_images", false)

    # CRITICAL FIX: We need to set the flag explicitly to true if it's true in the args
    # And this needs to be accessible throughout the job
    if force_refresh_images do
      Logger.info("⚠️ Force image refresh enabled - will refresh ALL images regardless of existing state")
      # Store in process dictionary for access in other functions
      Process.put(:force_refresh_images, true)
    else
      # Explicitly set to false to ensure it's not using a stale value
      Process.put(:force_refresh_images, false)
    end

    # Now we can see the process dictionary value for debugging
    Logger.info("📝 Process dictionary force_refresh_images set to: #{inspect(Process.get(:force_refresh_images))}")

    try do
      # Get source
      source = Repo.get!(Source, source_id)

      # Fetch venue details
      venue_url = venue_data["url"]
      Logger.info("🔍 Using venue URL: #{inspect(venue_url)}")

      # Check if URL is valid before proceeding
      if is_nil(venue_url) or venue_url == "" or not String.starts_with?(venue_url, "http") do
        error_msg = "Invalid venue URL: #{inspect(venue_url)}"
        Logger.error("❌ #{error_msg}")
        {:error, error_msg}
      else
        case HTTPoison.get(venue_url, [], follow_redirect: true) do
          {:ok, %{status_code: 200, body: body}} ->
            # Extract details
            details = Extractor.extract_venue_details(body)

            # Create venue attributes
            venue_attrs = %{
              name: venue_data["name"],
              address: details.address || venue_data["address"] || "",
              phone: details.phone,
              website: venue_url,
              # Skip image processing during initial venue creation
              skip_image_processing: true
            }

            # Process venue through VenueStore
            Logger.info("🔄 Processing venue through VenueStore: #{venue_attrs.name}")

            case VenueStore.process_venue(venue_attrs) do
              {:ok, venue} ->
                # Schedule separate job for Google Place lookup
                Logger.info("🔄 Scheduling Google Place lookup job for venue: #{venue.name}")
                schedule_place_lookup(venue)

                # IMPLEMENTATION: Delete any existing hero images for this venue if force_refresh_images is true
                # This ensures images are deleted even if there's no existing event with a hero_image in the DB
                if force_refresh_images do
                  # Get venue slug for directory path
                  venue_slug = venue.slug

                  # Log the operation
                  Logger.info("🧨 Force refresh enabled - cleaning venue images directory for #{venue.name}")

                  # Construct the directory path
                  venue_images_dir = Path.join(["priv/static/uploads/venues", venue_slug])

                  # Check if directory exists before attempting to clean it
                  if File.exists?(venue_images_dir) do
                    # Log files found
                    case File.ls(venue_images_dir) do
                      {:ok, files} ->
                        Logger.info("🗑️ Found #{length(files)} files to delete in #{venue_images_dir}")
                        Enum.each(files, fn file ->
                          file_path = Path.join(venue_images_dir, file)
                          Logger.info("🗑️ Deleting file: #{file_path}")
                          File.rm(file_path)
                        end)
                      {:error, reason} ->
                        Logger.error("❌ Failed to list files in venue directory: #{inspect(reason)}")
                    end
                  else
                    Logger.info("ℹ️ No existing venue image directory found at #{venue_images_dir}")
                  end
                end

                # Extract event details
                {day_of_week, start_time, entry_fee_cents} = extract_event_details(body)
                Logger.info("🔥 EXTRACTED EVENT DETAILS - Day: #{day_of_week}, Time: #{inspect(start_time)}, Fee: #{entry_fee_cents} cents")

                # Process performer if available from host information
                performer_id = if details.host && String.trim(details.host) != "" do
                  Logger.info("🎭 Found performer (host) information: #{details.host}")
                  case TriviaAdvisor.Events.Performer.find_or_create(%{
                    name: details.host,
                    source_id: source.id
                  }) do
                    {:ok, performer} ->
                      Logger.info("🎭 Successfully created/found performer: #{performer.name} (ID: #{performer.id})")
                      performer.id
                    {:error, reason} ->
                      Logger.error("❌ Failed to create performer: #{inspect(reason)}")
                      nil
                  end
                else
                  Logger.info("ℹ️ No performer (host) information found")
                  nil
                end

                # Format event data for EventStore
                # Must use English day names because EventStore.parse_day_of_week expects them
                day_name = case day_of_week do
                  0 -> "Sunday"
                  1 -> "Monday"
                  2 -> "Tuesday"
                  3 -> "Wednesday"
                  4 -> "Thursday"
                  5 -> "Friday"
                  6 -> "Saturday"
                  _ -> "Monday"
                end

                # Get force_refresh_images from process dictionary for hero image download
                force_refresh_images = Process.get(:force_refresh_images, false)
                Logger.info("🖼️ Using force_refresh_images=#{inspect(force_refresh_images)} for hero image processing")

                # Handle hero image if provided
                hero_image_url = venue_data["image_url"] || ""
                hero_image_attrs = if hero_image_url != "" do
                  Logger.info("🖼️ Processing hero image for venue: #{venue.name}")
                  case ImageDownloader.download_event_hero_image(hero_image_url, force_refresh_images) do
                    {:ok, upload} ->
                      Logger.info("✅ Successfully downloaded hero image for #{venue.name}")
                      # Create a map with both the hero_image and venue_id to help Waffle
                      # The venue_id is needed for proper S3 storage path construction
                      %{
                        hero_image: upload,
                        # Include venue_id to help with storage path generation in hero_image.ex
                        venue_id: venue.id
                      }
                    {:error, reason} ->
                      Logger.warning("⚠️ Failed to download hero image for #{venue.name}: #{inspect(reason)}")
                      %{}
                  end
                else
                  Logger.debug("ℹ️ No hero image URL provided for venue: #{venue.name}")
                  %{}
                end

                # Enhanced logging for debugging
                Logger.debug("🏆 Hero image attributes: #{inspect(hero_image_attrs)}")

                # Create the event data map with string keys
                event_data = %{
                  "source_url" => venue_url,
                  "raw_title" => "#{source.name} at #{venue.name}",
                  "name" => "#{source.name} at #{venue.name}",
                  "venue_id" => venue.id,
                  "venue_name" => venue.name,
                  "time_text" => "#{day_name} #{start_time}",
                  "fee_text" => "#{trunc(entry_fee_cents / 100)}",  # Format as integer like "15" without decimal or currency symbol
                  "description" => details.description || "",
                  "hero_image_url" => hero_image_url, # Keep original URL for metadata
                  "source" => "pubquiz",
                  "day_of_week" => day_of_week,
                  "start_time" => start_time,
                  "frequency" => :weekly,
                  "entry_fee_cents" => entry_fee_cents,
                  # Add explicit override that will be used directly in EventStore
                  "override_entry_fee_cents" => entry_fee_cents,
                  "performer_id" => performer_id
                }
                |> Map.merge(hero_image_attrs) # Add pre-processed hero image if available

                Logger.info("🔥 EVENT DATA BEING SENT TO EVENT STORE: #{inspect(event_data)}")
                Logger.info("🔍 SOURCE URL BEING SAVED: #{venue_url}")

                # Process event through EventStore
                Logger.info("🔄 Creating event for venue: #{venue.name}")

                # Process the event and handle the result - PASS force_refresh_images explicitly to EventStore
                event_result = EventStore.process_event(venue, event_data, source.id, force_refresh_images: force_refresh_images)
                Logger.info("🔍 EventStore.process_event result: #{inspect(event_result)}")

                case event_result do
                  {:ok, {:ok, event}} ->
                    # Log the created event details
                    Logger.info("🔥 CREATED EVENT - ID: #{event.id}, Name: #{event.name}, Day: #{event.day_of_week}, Time: #{event.start_time}, Fee: #{event.entry_fee_cents}")

                    # Create metadata for reporting
                    metadata = %{
                      "venue_name" => venue.name,
                      "venue_id" => venue.id,
                      "venue_url" => venue_url,
                      "event_id" => event.id,
                      "address" => venue.address,
                      "phone" => venue.phone,
                      "host" => details.host || "",
                      "description" => details.description || "",
                      "source_name" => source.name,
                      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
                      "day_of_week" => day_of_week,
                      "start_time" => Time.to_string(start_time),
                      "entry_fee_cents" => entry_fee_cents,
                      "force_refresh_images" => force_refresh_images # Include flag in metadata
                    }

                    # Update job metadata using JobMetadata helper
                    JobMetadata.update_detail_job(job_id, metadata, {:ok, event})

                    # Log success
                    Logger.info("✅ Successfully processed venue and event for #{venue.name}")
                    {:ok, metadata}

                  {:ok, {:error, reason}} ->
                    Logger.error("❌ Failed to create event: #{inspect(reason)}")
                    {:error, "Failed to create event: #{inspect(reason)}"}

                  {:error, reason} ->
                    Logger.error("❌ Failed to create event: #{inspect(reason)}")
                    {:error, "Failed to create event: #{inspect(reason)}"}
                end

              {:error, reason} ->
                Logger.error("❌ Failed to process venue: #{inspect(reason)}")
                {:error, reason}
            end

          {:ok, %{status_code: status}} ->
            error = "Failed to fetch venue details. Status: #{status}"
            Logger.error("❌ #{error}")
            {:error, error}

          {:error, error} ->
            error_msg = "Failed to fetch venue details: #{inspect(error)}"
            Logger.error("❌ #{error_msg}")
            {:error, error_msg}
        end
      end
    rescue
      e ->
        error_msg = "Failed to process venue: #{Exception.message(e)}"
        Logger.error("❌ #{error_msg}")
        Logger.error("❌ Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        {:error, error_msg}
    end
  end

  # Extract event details (day_of_week, start_time, entry_fee_cents) from page content
  defp extract_event_details(body) do
    # Extract product titles which contain day and time info
    product_titles = Regex.scan(~r/<h3 class="product-title">(.*?)<\/h3>/s, body)
      |> Enum.map(fn [_, title] -> title end)

    Logger.debug("🔍 Found product titles: #{inspect(product_titles)}")

    # Try several different regex patterns for price extraction
    price_patterns = [
      # Pattern 1: Standard format
      ~r/<span class="woocommerce-Price-amount amount">(.*?)&nbsp;<span class="woocommerce-Price-currencySymbol">zł<\/span><\/span>/s,
      # Pattern 2: Alternative format
      ~r/<span class="product-price price"><span class="woocommerce-Price-amount amount">(.*?)&nbsp;<span class="woocommerce-Price-currencySymbol">zł<\/span><\/span>/s,
      # Pattern 3: More general pattern
      ~r/<span class="woocommerce-Price-amount amount">(.*?)&nbsp;/s
    ]

    # Try each pattern until we find prices
    price_texts = Enum.reduce_while(price_patterns, [], fn pattern, acc ->
      results = Regex.scan(pattern, body) |> Enum.map(fn [_, price] -> price end)
      if Enum.empty?(results), do: {:cont, acc}, else: {:halt, results}
    end)

    Logger.debug("🔍 Found price texts: #{inspect(price_texts)}")

    # Look for the iworks-omnibus divs which might contain price info
    omnibus_divs = Regex.scan(~r/<p class="iworks-omnibus".*?data-iwo-price="(.*?)".*?>/s, body)
      |> Enum.map(fn [_, price] -> price end)
    Logger.debug("🔍 Found omnibus price data: #{inspect(omnibus_divs)}")

    # Check if we have anything usable
    if Enum.empty?(price_texts) && Enum.empty?(omnibus_divs) && Enum.empty?(product_titles) do
      Logger.warning("⚠️ Could not extract price or time information. Using defaults.")
      {1, ~T[19:00:00], 0}  # Default: Monday, 7pm, Free
    else
      # Extract the best day, time, and price information we can
      # First try to extract day and time from product titles
      {day_number, start_time} =
        case Enum.find(product_titles, fn title ->
          Enum.any?(@polish_days, fn {day_name, _} -> String.contains?(title, day_name) end)
        end) do
          nil ->
            # No day information found, use defaults
            Logger.warning("⚠️ No day information found in product titles. Using defaults.")
            {1, ~T[19:00:00]}  # Default: Monday, 7pm
          title ->
            # Try to extract day
            day_match = Enum.find(@polish_days, fn {day_name, _} ->
              String.contains?(String.upcase(title), day_name)
            end)

            day_number = case day_match do
              {_, num} -> num
              _ -> 1  # Default if extraction fails
            end

            # Try to extract time
            time_match = Regex.run(~r/(\d{1,2}):(\d{2})/, title)
            start_time = case time_match do
              [_, hours, minutes] ->
                {hours, _} = Integer.parse(hours)
                {minutes, _} = Integer.parse(minutes)
                Time.new!(hours, minutes, 0)
              _ ->
                # No time in title, check content for time
                time_content_match = Regex.run(~r/(\d{1,2}):(\d{2})/, body)
                case time_content_match do
                  [_, hours, minutes] ->
                    {hours, _} = Integer.parse(hours)
                    {minutes, _} = Integer.parse(minutes)
                    Time.new!(hours, minutes, 0)
                  _ ->
                    ~T[19:00:00]  # Default: 7pm
                end
            end

            {day_number, start_time}
        end

      # Process price information
      entry_fee_cents = cond do
        # Try omnibus price first as it's most reliable
        !Enum.empty?(omnibus_divs) ->
          price = List.first(omnibus_divs)
          {price_float, _} = Float.parse(price)
          trunc(price_float * 100)  # Convert to cents

        # Then try price spans
        !Enum.empty?(price_texts) ->
          # Clean up price text (remove commas, etc)
          price = List.first(price_texts)
                  |> String.replace(",", ".")
                  |> String.replace(~r/[^\d.]/, "")
          case Float.parse(price) do
            {price_float, _} -> trunc(price_float * 100)  # Convert to cents
            :error -> 0  # Default to free if parsing fails
          end

        # Default to free
        true ->
          0
      end

      # Return the extracted or default values
      {day_number, start_time, entry_fee_cents}
    end
  end

  # Schedule Google Place lookup job
  defp schedule_place_lookup(venue) do
    case GooglePlaceLookupJob.new(%{venue_id: venue.id}) do
      %{errors: []} = job ->
        {:ok, _job} = Oban.insert(job)
        Logger.info("📥 Scheduled Google Place lookup job for #{venue.name}")
      %{errors: errors} ->
        Logger.error("❌ Failed to schedule Google Place lookup job for #{venue.name}: #{inspect(errors)}")
    end
  end
end

defmodule TriviaAdvisor.Scraping.Oban.PubquizDetailJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Scraping.Oban.PubquizPlaceLookupJob

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
  def perform(%Oban.Job{args: %{"venue_data" => venue_data, "source_id" => source_id}, id: job_id}) do
    Logger.info("🔄 Processing venue: #{venue_data["name"]}")

    try do
      # Get source
      source = Repo.get!(Source, source_id)

      # Fetch venue details
      case HTTPoison.get(venue_data["url"], [], follow_redirect: true) do
        {:ok, %{status_code: 200, body: body}} ->
          # Extract details
          details = Extractor.extract_venue_details(body)

          # Create venue attributes
          venue_attrs = %{
            name: venue_data["name"],
            address: details.address || venue_data["address"] || "",
            phone: details.phone,
            website: venue_data["url"],
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

              # Extract event details
              {day_of_week, start_time, entry_fee_cents} = extract_event_details(body)
              Logger.info("🔥 EXTRACTED EVENT DETAILS - Day: #{day_of_week}, Time: #{inspect(start_time)}, Fee: #{entry_fee_cents} cents")

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

              # Create the event data map with string keys
              event_data = %{
                "raw_title" => "#{source.name} at #{venue.name}",
                "name" => "#{source.name} at #{venue.name}", # Make sure name is properly set
                "time_text" => "#{day_name} #{start_time}",
                "description" => details.description || "",
                "fee_text" => "#{trunc(entry_fee_cents / 100)}",  # Format as integer like "15" without decimal or currency symbol
                "source_url" => venue_data["url"],
                "hero_image_url" => venue_data["image_url"] || "",
                "day_of_week" => day_of_week,
                "start_time" => start_time,
                "frequency" => :weekly,
                "entry_fee_cents" => entry_fee_cents,
                # Add explicit override that will be used directly in EventStore
                "override_entry_fee_cents" => entry_fee_cents
              }

              Logger.info("🔥 EVENT DATA BEING SENT TO EVENT STORE: #{inspect(event_data)}")

              # Process event through EventStore
              Logger.info("🔄 Creating event for venue: #{venue.name}")

              # Process the event and handle the result
              event_result = EventStore.process_event(venue, event_data, source.id)
              Logger.info("🔍 EventStore.process_event result: #{inspect(event_result)}")

              case event_result do
                {:ok, {:ok, event}} ->
                  # Log the created event details
                  Logger.info("🔥 CREATED EVENT - ID: #{event.id}, Name: #{event.name}, Day: #{event.day_of_week}, Time: #{event.start_time}, Fee: #{event.entry_fee_cents}")

                  # Create metadata for reporting
                  metadata = %{
                    "venue_name" => venue.name,
                    "venue_id" => venue.id,
                    "venue_url" => venue_data["url"],
                    "event_id" => event.id,
                    "address" => venue.address,
                    "phone" => venue.phone,
                    "host" => details.host || "",
                    "description" => details.description || "",
                    "source_name" => source.name,
                    "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
                    "day_of_week" => day_of_week,
                    "start_time" => Time.to_string(start_time),
                    "entry_fee_cents" => entry_fee_cents
                  }

                  # Update job metadata
                  query = from(job in "oban_jobs", where: job.id == type(^job_id, :integer))
                  Repo.update_all(query, set: [meta: metadata])

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

    if Enum.empty?(product_titles) do
      Logger.warning("⚠️ No product titles found on page")
      {1, ~T[19:00:00], 0} # Default values if nothing found
    else
      # Take the first product as representative
      product_title = List.first(product_titles)
      Logger.debug("🔍 Using product title: #{product_title}")

      # Extract day of week from within brackets [DAY]
      day_of_week = case Regex.run(~r/\[(.*?)\]/, product_title) do
        [_, polish_day] ->
          numeric_day = Map.get(@polish_days, polish_day, 1)
          Logger.debug("🔍 Extracted day of week: #{polish_day} -> #{numeric_day}")
          numeric_day
        _ ->
          Logger.warning("⚠️ Could not extract day of week from title: #{product_title}")
          1 # Default to Monday if not found
      end

      # Extract time (usually at the end of the title like "20:00")
      start_time = case Regex.run(~r/(\d{2}:\d{2})$/, product_title) do
        [_, time_str] ->
          [hours, minutes] = String.split(time_str, ":")
          time = Time.new!(String.to_integer(hours), String.to_integer(minutes), 0)
          Logger.debug("🔍 Extracted time: #{time_str} -> #{time}")
          time
        _ ->
          Logger.warning("⚠️ Could not extract time from title: #{product_title}")
          ~T[19:00:00] # Default time if not found
      end

      # Extract price (if available)
      entry_fee_cents = cond do
        # Try omnibus data first (most reliable)
        !Enum.empty?(omnibus_divs) ->
          price_text = List.first(omnibus_divs)
          {price, _} = Float.parse(price_text)
          cents = round(price * 100)
          Logger.debug("🔍 Extracted price from omnibus data: #{price_text} -> #{cents} cents")
          cents

        # Then try price spans
        !Enum.empty?(price_texts) ->
          price_text = List.first(price_texts)
          # Convert price like "15,00" to cents (1500)
          price_text
          |> String.replace(",", ".")
          |> Float.parse()
          |> case do
            {price, _} ->
              cents = round(price * 100)
              Logger.debug("🔍 Extracted price: #{price_text} -> #{cents} cents")
              cents
            :error ->
              Logger.warning("⚠️ Could not parse price: #{price_text}")
              1500 # Default to 15 zł if parsing fails
          end

        # Default if no price found
        true ->
          Logger.warning("⚠️ No price found on page")
          1500 # Default to 15 zł (typical price for these events)
      end

      Logger.info("📊 Event details extracted - Day: #{day_of_week}, Time: #{start_time}, Price: #{entry_fee_cents} cents")
      {day_of_week, start_time, entry_fee_cents}
    end
  end

  # Schedules a separate job for Google Place API lookups
  defp schedule_place_lookup(venue) do
    # Create a job with the venue ID
    %{"venue_id" => venue.id}
    |> PubquizPlaceLookupJob.new()
    |> Oban.insert()
  end

  # Helper to extract entry fee from details
end

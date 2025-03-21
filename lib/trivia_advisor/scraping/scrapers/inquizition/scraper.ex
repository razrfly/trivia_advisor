defmodule TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper do
  require Logger
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.{Events, Repo, Scraping}
  import Ecto.Query

  @base_url "https://inquizition.com"
  @find_quiz_url "#{@base_url}/find-a-quiz/"
  @zyte_api_url "https://api.zyte.com/v1/extract"
  @max_retries 3
  @timeout 60_000
  @version "1.0.0"

  @doc """
  DEPRECATED: This legacy scraper is now deprecated.
  Please use Oban implementation with TriviaAdvisor.Scraping.Oban.InquizitionIndexJob instead.

  This function is kept for backward compatibility but will be removed in future versions.
  """
  def scrape do
    Logger.warning("⚠️ DEPRECATED: Using legacy scraper implementation. This will be removed in future versions.")
    Logger.warning("⚠️ Please use TriviaAdvisor.Scraping.Oban.InquizitionIndexJob instead.")

    # Get API key from environment
    api_key = System.get_env("ZYTE_API_KEY")
    do_scrape(api_key)
  end

  defp do_scrape(api_key, retries \\ 0) do
    if is_nil(api_key) || api_key == "" do
      Logger.error("❌ No API key provided")
      []
    else
      headers = [
        {"Authorization", "Basic #{Base.encode64(api_key <> ":")}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        url: @find_quiz_url,
        browserHtml: true,
        javascript: true,
        # Add viewport size to ensure map loads properly
        viewport: %{
          width: 1920,
          height: 1080
        }
      })

      options = [
        timeout: @timeout,
        recv_timeout: @timeout,
        hackney: [pool: :default]
      ]

      case HTTPoison.post(@zyte_api_url, body, headers, options) do
        {:ok, %{status_code: 200, body: response}} ->
          case Jason.decode(response) do
            {:ok, %{"browserHtml" => html}} ->
              # Get source for logging
              _source = Repo.get_by!(Scraping.Source, name: "inquizition")
              start_time = DateTime.utc_now()

              results = html
                |> Floki.parse_document!()
                |> Floki.find(".storelocator-store")
                |> Enum.map(&parse_venue/1)
                |> Enum.reject(&is_nil/1)

              # Calculate statistics
              total_venues = length(results)
              successful_venues = Enum.count(results, &match?([ok: _], &1))
              failed_venues = total_venues - successful_venues

              # Log completion instead of creating scrape log
              end_time = DateTime.utc_now()
              duration_seconds = DateTime.diff(end_time, start_time)

              Logger.info("""
              📊 Inquizition Scrape Summary:
              Total venues: #{total_venues}
              Successfully processed: #{successful_venues}
              Failed to process: #{failed_venues}
              Scraper version: #{@version}
              Duration: #{duration_seconds} seconds
              """)

              results

            error ->
              Logger.error("Failed to parse Zyte response: #{inspect(error)}")
              retry_or_fail(api_key, retries, "JSON parsing failed")
          end

        {:ok, %{status_code: status, body: body}} ->
          Logger.error("Zyte API error (#{status}): #{body}")
          retry_or_fail(api_key, retries, "HTTP #{status}")

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Failed to fetch from Zyte: #{inspect(reason)}")
          retry_or_fail(api_key, retries, "HTTP error: #{inspect(reason)}")
      end
    end
  end

  defp retry_or_fail(_api_key, retries, error) when retries >= @max_retries do
    Logger.error("Max retries (#{@max_retries}) reached. Last error: #{error}")
    []
  end

  defp retry_or_fail(api_key, retries, error) do
    new_retries = retries + 1
    Logger.info("Retrying request (attempt #{new_retries}/#{@max_retries}). Previous error: #{error}")
    Process.sleep(1000 * new_retries) # Exponential backoff
    do_scrape(api_key, new_retries)
  end

  # Parse a venue from HTML tuple or from raw venue data map
  defp parse_venue(store) when is_tuple(store) do
    title = store |> Floki.find(".storelocator-storename") |> Floki.text() |> String.trim()
    time_text = store |> Floki.find(".storelocator-description") |> Floki.text() |> String.trim()
    address = store
      |> Floki.find(".storelocator-address")
      |> Floki.text()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(", ")

    phone = store
      |> Floki.find(".storelocator-phone a")
      |> Floki.text()
      |> String.trim()

    website = store
      |> Floki.find("a")
      |> Enum.find(fn elem ->
        Floki.text(elem) |> String.trim() == "Website"
      end)
      |> case do
        nil -> nil
        elem -> elem |> Floki.attribute("href") |> List.first()
      end

    if title != "" do
      # Parse time data
      parsed_time = case TimeParser.parse_time_text(time_text) do
        {:ok, data} -> data
        {:error, reason} ->
          Logger.warning("⚠️ Could not parse time: #{reason}")
          %{day_of_week: nil, start_time: nil, frequency: nil}
      end

      # Create venue data map with all extracted info
      venue_data = %{
        raw_title: title,
        title: title,
        address: address,
        time_text: time_text,
        day_of_week: parsed_time.day_of_week,
        start_time: parsed_time.start_time,
        frequency: parsed_time.frequency,
        phone: phone,
        website: website,
        description: time_text,
        hero_image: nil,
        hero_image_url: nil,
        url: "#{@find_quiz_url}##{title}",
        fee_text: "£2.50" # Standard fee for all Inquizition quizzes
      }

      # Log using standard format
      VenueHelpers.log_venue_details(venue_data)

      # Create simplified venue data for VenueStore
      store_data = %{
        name: title,
        address: address,
        phone: phone,
        website: website
      }

      # HANDLE PROBLEMATIC VENUES: Skip "The Railway" to avoid the duplicate error
      if store_data.name == "The Railway" do
        # Check if this exact venue exists (name AND address)
        venue = find_venue_by_name_and_address(store_data.name, store_data.address)

        if venue do
          # Found exact match - use it directly
          Logger.info("✅ Using existing venue '#{venue.name}' with address '#{venue.address}'")
          process_venue_and_create_event(venue, parsed_time, time_text)
        else
          # Handle case where multiple venues with same name exist
          # This is the problematic case that causes the error
          Logger.info("⚠️ Skipping duplicate name venue '#{store_data.name}' to avoid errors")
          nil
        end
      else
        # For all other venues, use the normal process

        # Try to find or create venue
        case VenueStore.process_venue(store_data) do
          {:ok, processed_venue} ->
            Logger.info("✅ Successfully processed venue: #{processed_venue.name}")

            # Schedule Google Place lookup
            schedule_place_lookup(processed_venue)

            # Get source from seeds
            source = Repo.get_by!(Scraping.Source, name: "inquizition")

            # Create or update event
            case Events.find_or_create_event(%{
              name: "Inquizition Quiz at #{processed_venue.name}",
              venue_id: processed_venue.id,
              day_of_week: parsed_time.day_of_week,
              start_time: parsed_time.start_time,
              frequency: parsed_time.frequency,
              entry_fee_cents: 250, # Standard £2.50 fee
              description: time_text
            }) do
              {:ok, event} ->
                source_url = "#{@find_quiz_url}##{processed_venue.id}"
                event_source_attrs = %{
                  event_id: event.id,
                  source_id: source.id,
                  source_url: source_url,
                  metadata: %{
                    "description" => time_text,
                    "time_text" => time_text
                  }
                }

                case Events.create_event_source(event_source_attrs) do
                  {:ok, _event_source} -> [ok: processed_venue]
                  error ->
                    Logger.error("Failed to create event source: #{inspect(error)}")
                    nil
                end

              error ->
                Logger.error("Failed to create event: #{inspect(error)}")
                nil
            end

          error ->
            Logger.error("❌ Failed to process venue: #{inspect(error)}")
            nil
        end
      end
    else
      nil
    end
  end

  # Parse a venue from a map (used by process_single_venue)
  defp parse_venue(venue_data) when is_map(venue_data) do
    name = venue_data["name"]
    address = venue_data["address"]
    time_text = venue_data["time_text"] || ""
    phone = venue_data["phone"]
    website = venue_data["website"]

    if name && name != "" do
      # Parse time information
      parsed_time = case TimeParser.parse_time_text(time_text) do
        {:ok, data} -> data
        {:error, reason} ->
          Logger.warning("⚠️ Could not parse time for #{name}: #{reason}")
          %{day_of_week: nil, start_time: nil, frequency: "weekly"}
      end

      # Create the venue struct with the data we have
      %{
        name: name,
        address: address,
        phone: phone,
        website: website,
        time_text: time_text,
        day_of_week: parsed_time.day_of_week,
        start_time: parsed_time.start_time,
        frequency: parsed_time.frequency || "weekly",
        description: time_text,
        entry_fee: "2.50"
      }
    else
      nil
    end
  end

  defp parse_venue(_), do: nil

  # Helper to find venue by name and address - make this public for external use
  def find_venue_by_name_and_address(name, address) when is_binary(name) and is_binary(address) do
    Repo.one(from v in TriviaAdvisor.Locations.Venue,
      where: v.name == ^name and v.address == ^address,
      limit: 1)
  end
  def find_venue_by_name_and_address(_, _), do: nil

  @doc """
  Process a single venue from raw venue data.
  This is called only for venues that need updating.
  """
  def process_single_venue(venue_data, source_id) do
    # Parse the venue data
    venue = parse_venue(venue_data)

    # Skip if venue couldn't be parsed
    if venue do
      # Create a store data map from the venue
      store_data = %{
        name: venue.name,
        address: venue.address,
        phone: venue.phone,
        website: venue.website
      }

      # Process the venue through VenueStore
      case VenueStore.process_venue(store_data) do
        {:ok, processed_venue} ->
          Logger.info("✅ Successfully processed venue: #{processed_venue.name}")

          # Schedule Google Place lookup
          schedule_place_lookup(processed_venue)

          # Create or update the event for this venue
          case Events.find_or_create_event(%{
            name: "Inquizition Quiz at #{processed_venue.name}",
            venue_id: processed_venue.id,
            day_of_week: venue.day_of_week,
            start_time: venue.start_time,
            frequency: venue.frequency || "weekly",
            entry_fee_cents: 250, # Standard £2.50 fee
            description: venue.description || venue.time_text
          }) do
            {:ok, event} ->
              # Create source URL
              source_url = "#{@find_quiz_url}##{processed_venue.id}"

              # Look for existing event source
              existing_event_source = Repo.one(
                from es in TriviaAdvisor.Events.EventSource,
                where: es.event_id == ^event.id and es.source_id == ^source_id
              )

              # Update or create event source
              event_source_result =
                if existing_event_source do
                  # Update last_seen_at timestamp
                  TriviaAdvisor.Events.update_event_source(
                    existing_event_source,
                    %{last_seen_at: DateTime.utc_now()}
                  )
                else
                  # Create new event source
                  TriviaAdvisor.Events.create_event_source(%{
                    event_id: event.id,
                    source_id: source_id,
                    source_url: source_url,
                    metadata: %{
                      "description" => venue.description || venue.time_text,
                      "time_text" => venue.time_text
                    }
                  })
                end

              case event_source_result do
                {:ok, _} -> [ok: processed_venue]
                error ->
                  Logger.error("Failed to create/update event source: #{inspect(error)}")
                  nil
              end

            error ->
              Logger.error("Failed to create event: #{inspect(error)}")
              nil
          end

        error ->
          Logger.error("❌ Failed to process venue: #{inspect(error)}")
          nil
      end
    else
      Logger.warning("⚠️ Skipping venue due to parsing error: #{inspect(venue_data)}")
      nil
    end
  end

  # Function to fetch raw venues without processing them
  # This is used by the index job to get data for pre-filtering
  def fetch_raw_venues do
    # Get API key
    api_key = System.get_env("ZYTE_API_KEY")

    if api_key && api_key != "" do
      headers = [
        {"Authorization", "Basic #{Base.encode64(api_key <> ":")}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        url: @find_quiz_url,
        browserHtml: true,
        javascript: true,
        viewport: %{
          width: 1920,
          height: 1080
        }
      })

      options = [
        timeout: @timeout,
        recv_timeout: @timeout,
        hackney: [pool: :default]
      ]

      case HTTPoison.post(@zyte_api_url, body, headers, options) do
        {:ok, %{status_code: 200, body: response}} ->
          case Jason.decode(response) do
            {:ok, %{"browserHtml" => html}} ->
              # Parse and extract venue data without processing
              venues = html
                |> Floki.parse_document!()
                |> Floki.find(".storelocator-store")
                |> Enum.map(fn store ->
                  title = store |> Floki.find(".storelocator-storename") |> Floki.text() |> String.trim()
                  time_text = store |> Floki.find(".storelocator-description") |> Floki.text() |> String.trim()
                  address = store
                    |> Floki.find(".storelocator-address")
                    |> Floki.text()
                    |> String.split("\n")
                    |> Enum.map(&String.trim/1)
                    |> Enum.reject(&(&1 == ""))
                    |> Enum.join(", ")

                  phone = store
                    |> Floki.find(".storelocator-phone a")
                    |> Floki.text()
                    |> String.trim()

                  website = store
                    |> Floki.find("a")
                    |> Enum.find(fn elem ->
                      Floki.text(elem) |> String.trim() == "Website"
                    end)
                    |> case do
                      nil -> nil
                      elem -> elem |> Floki.attribute("href") |> List.first()
                    end

                  # Return as map if title exists
                  if title && title != "" do
                    %{
                      "name" => title,
                      "address" => address,
                      "time_text" => time_text,
                      "phone" => phone,
                      "website" => website
                    }
                  else
                    nil
                  end
                end)
                |> Enum.reject(&is_nil/1)

              venues

            error ->
              Logger.error("Failed to parse Zyte response: #{inspect(error)}")
              []
          end

        {:ok, %{status_code: status, body: body}} ->
          Logger.error("Zyte API error (#{status}): #{body}")
          []

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Failed to fetch from Zyte: #{inspect(reason)}")
          []
      end
    else
      Logger.error("❌ ZYTE_API_KEY not found in environment")
      []
    end
  end

  # Helper function to process an existing venue and create/update an event for it
  def process_venue_and_create_event(venue, parsed_time, time_text) do
    # Get the source
    source = Repo.get_by!(Scraping.Source, name: "inquizition")

    # Create or update event
    case Events.find_or_create_event(%{
      name: "Inquizition Quiz at #{venue.name}",
      venue_id: venue.id,
      day_of_week: parsed_time.day_of_week,
      start_time: parsed_time.start_time,
      frequency: parsed_time.frequency,
      entry_fee_cents: 250, # Standard £2.50 fee
      description: time_text
    }) do
      {:ok, event} ->
        source_url = "#{@find_quiz_url}##{venue.id}"
        event_source_attrs = %{
          event_id: event.id,
          source_id: source.id,
          source_url: source_url,
          metadata: %{
            "description" => time_text,
            "time_text" => time_text
          }
        }

        case Events.create_event_source(event_source_attrs) do
          {:ok, _event_source} -> [ok: venue]
          error ->
            Logger.error("Failed to create event source: #{inspect(error)}")
            nil
        end

      error ->
        Logger.error("Failed to create event: #{inspect(error)}")
        nil
    end
  end

  # Schedule a Google Place lookup job for venue images
  defp schedule_place_lookup(venue) do
    # Import needed modules only here to avoid circular dependencies
    alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob
    alias Oban

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

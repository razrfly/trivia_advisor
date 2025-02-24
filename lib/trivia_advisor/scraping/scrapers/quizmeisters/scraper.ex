defmodule TriviaAdvisor.Scraping.Scrapers.Quizmeisters do
  @moduledoc """
  Scraper for Quizmeisters venues and events.
  """

  alias TriviaAdvisor.Scraping.{ScrapeLog, Source}
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers}
  alias TriviaAdvisor.Scraping.Scrapers.Quizmeisters.VenueExtractor
  alias TriviaAdvisor.{Locations, Repo}
  alias TriviaAdvisor.Events
  require Logger

  @base_url "https://quizmeisters.com"
  @api_url "https://storerocket.io/api/user/kDJ3BbK4mn/locations"
  @version "1.0.0"

  @doc """
  Main entry point for the scraper.
  """
  def run do
    Logger.info("Starting Quizmeisters scraper")

    # Check for .env file and load if present
    if File.exists?(".env") do
      DotenvParser.load_file(".env")
      Logger.info("📝 Loaded .env file")
    end

    # Verify API key is available
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 ->
        Logger.info("🔑 API key loaded successfully")
        do_run()

      _ ->
        Logger.error("❌ GOOGLE_MAPS_API_KEY not found in environment")
        System.halt(1)
    end
  end

  defp do_run do
    source = Repo.get_by!(Source, website_url: @base_url)
    start_time = DateTime.utc_now()

    case ScrapeLog.create_log(source) do
      {:ok, log} ->
        Logger.info("Created scrape log")
        try do
          case fetch_venues() do
            {:ok, venues} ->
              venue_count = length(venues)
              Logger.info("Found #{venue_count} venues")

              detailed_venues = venues
              |> Enum.map(&parse_venue/1)
              |> Enum.reject(&is_nil/1)
              |> Enum.map(&fetch_venue_details(&1, source))
              |> Enum.reject(&is_nil/1)

              successful_venues = length(detailed_venues)
              failed_venues = venue_count - successful_venues

              metadata = %{
                "venues" => detailed_venues,
                "started_at" => DateTime.to_iso8601(start_time),
                "completed_at" => DateTime.to_iso8601(DateTime.utc_now()),
                "total_venues" => venue_count,
                "successful_venues" => successful_venues,
                "failed_venues" => failed_venues,
                "scraper_version" => @version
              }

              ScrapeLog.update_log(log, %{
                success: true,
                total_venues: venue_count,
                metadata: metadata
              })

              {:ok, detailed_venues}

            {:error, reason} ->
              Logger.error("Scraping failed: #{reason}")
              {:error, reason}
          end
        rescue
          e ->
            ScrapeLog.log_error(log, e)
            Logger.error("Scraper failed: #{Exception.message(e)}")
            {:error, e}
        end

      {:error, reason} ->
        Logger.error("Failed to create scrape log: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_venues do
    case HTTPoison.get(@api_url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => %{"locations" => locations}}} when is_list(locations) ->
            {:ok, locations}

          {:error, reason} ->
            Logger.error("Failed to parse JSON response: #{inspect(reason)}")
            {:error, "Failed to parse JSON response"}

          _ ->
            Logger.error("Unexpected response format")
            {:error, "Unexpected response format"}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status}: Failed to fetch venues")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp parse_venue(location) do
    time_text = get_trivia_time(location)
    case TimeParser.parse_time_text(time_text) do
      {:ok, %{day_of_week: day_of_week, start_time: start_time}} ->
        # Build the full venue data for logging
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

        VenueHelpers.log_venue_details(venue_data)
        venue_data

      {:error, reason} ->
        Logger.error("Failed to parse time text: #{reason}")
        nil
    end
  end

  defp fetch_venue_details(venue_data, source) do
    Logger.info("Processing venue: #{venue_data.title}")

    case HTTPoison.get(venue_data.url, [], follow_redirect: true) do
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

          case Locations.VenueStore.process_venue(venue_store_data) do
            {:ok, venue} ->
              final_data = Map.put(merged_data, :venue_id, venue.id)
              VenueHelpers.log_venue_details(final_data)

              # Process the event
              event_data = %{
                name: "Quizmeisters Quiz at #{venue.name}",
                venue_id: venue.id,
                day_of_week: final_data.day_of_week,
                start_time: final_data.start_time,
                frequency: final_data.frequency,
                entry_fee_cents: 0, # Assuming free entry
                description: final_data.description
              }

              case Events.find_or_create_event(event_data) do
                {:ok, event} ->
                  # Create the event source
                  event_source_attrs = %{
                    event_id: event.id,
                    source_id: source.id,
                    source_url: venue_data.url,
                    metadata: %{
                      "description" => final_data.description,
                      "time_text" => final_data.time_text
                    }
                  }

                  case Events.create_event_source(event_source_attrs) do
                    {:ok, _event_source} ->
                      Logger.info("✅ Successfully processed event and event source for venue: #{venue.name}")
                      final_data
                    error ->
                      Logger.error("Failed to create event source: #{inspect(error)}")
                      nil
                  end

                error ->
                  Logger.error("Failed to create event: #{inspect(error)}")
                  nil
              end

            error ->
              Logger.error("Failed to process venue: #{inspect(error)}")
              nil
          end
        else
          {:error, reason} ->
            Logger.error("Failed to extract venue data: #{reason}")
            venue_data
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} when fetching venue: #{venue_data.url}")
        venue_data

      {:error, error} ->
        Logger.error("Error fetching venue #{venue_data.url}: #{inspect(error)}")
        venue_data
    end
  end

  defp get_trivia_time(location) do
    # Find trivia time in fields array
    fields = location["fields"] || []
    Enum.find_value(fields, "", fn field ->
      if field["name"] in ["Trivia", "Survey Says"], do: field["pivot_field_value"]
    end)
  end
end

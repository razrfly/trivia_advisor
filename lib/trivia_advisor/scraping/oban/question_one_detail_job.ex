defmodule TriviaAdvisor.Scraping.Oban.QuestionOneDetailJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.QuestionOne.VenueExtractor
  # Enable aliases for venue and event processing
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    url = Map.get(args, "url")
    title = Map.get(args, "title")
    source_id = Map.get(args, "source_id")

    Logger.info("🔄 Processing Question One venue: #{title}")

    # Get the Question One source
    source = Repo.get!(Source, source_id)

    # Process the venue using the existing logic
    result = fetch_venue_details(%{url: url, title: title}, source)

    # Debug log the exact structure we're getting
    Logger.debug("📊 Result structure: #{inspect(result)}")

    # Handle the result with better pattern matching
    handle_processing_result(result)
  end

  # A catch-all handler that logs the structure and converts to a standardized format
  defp handle_processing_result(result) do
    Logger.info("🔄 Processing result with structure: #{inspect(result)}")

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
  defp fetch_venue_details(%{url: url, title: raw_title}, source) do
    Logger.info("\n🔍 Processing venue: #{raw_title}")

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
            # Check if we should fetch Google Place images using the centralized function
            venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

            # Then process the event with the venue
            event_data = %{
              raw_title: raw_title,
              name: venue.name,
              time_text: extracted_data.time_text,
              description: extracted_data.description,
              fee_text: extracted_data.fee_text,
              hero_image_url: extracted_data.hero_image_url,
              source_url: url
            }

            case EventStore.process_event(venue, event_data, source.id) do
              {:ok, _event} ->
                Logger.info("✅ Successfully processed event for venue: #{venue.name}")
                {:ok, venue}
              {:error, reason} ->
                Logger.error("❌ Failed to process event: #{inspect(reason)}")
                {:error, reason}
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
end

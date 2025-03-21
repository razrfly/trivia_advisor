defmodule TriviaAdvisor.Scraping.Oban.QuestionOneDetailJob do
  use Oban.Worker,
    queue: :default,
    max_attempts: TriviaAdvisor.Scraping.RateLimiter.max_attempts(),
    priority: TriviaAdvisor.Scraping.RateLimiter.priority()

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.QuestionOne.VenueExtractor
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Scraping.Helpers.JobMetadata
  alias TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    url = Map.get(args, "url")
    title = Map.get(args, "title")
    source_id = Map.get(args, "source_id")

    Logger.info("🔄 Processing Question One venue: #{title}")

    # Get the Question One source
    source = Repo.get!(Source, source_id)

    # Process the venue using the existing logic
    result = fetch_venue_details(%{url: url, title: title}, source, job_id)

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
  defp fetch_venue_details(%{url: url, title: raw_title}, source, job_id) do
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
            # Schedule a separate job for Google Place lookup
            Logger.info("🔄 Scheduling Google Place lookup job for venue: #{venue.name}")
            schedule_place_lookup(venue)

            # Process the hero image using the centralized ImageDownloader
            hero_image_attrs = if extracted_data.hero_image_url && extracted_data.hero_image_url != "" do
              case ImageDownloader.download_event_hero_image(extracted_data.hero_image_url) do
                {:ok, upload} ->
                  Logger.info("✅ Successfully downloaded hero image for #{venue.name}")
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

            case EventStore.process_event(venue, event_data, source.id) do
              {:ok, {:ok, event}} ->
                Logger.info("✅ Successfully processed event for venue: #{venue.name}")

                # Create metadata for reporting
                metadata = %{
                  "venue_name" => venue.name,
                  "venue_id" => venue.id,
                  "venue_url" => url,
                  "event_id" => event.id,
                  "address" => venue.address,
                  "phone" => venue.phone || "",
                  "description" => extracted_data.description || "",
                  "source_name" => source.name,
                  "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
                  "time_text" => extracted_data.time_text || "",
                  "fee_text" => extracted_data.fee_text || ""
                }

                # Update job metadata
                JobMetadata.update_detail_job(job_id, metadata, %{
                  venue_id: venue.id,
                  event_id: event.id
                })

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

  # Schedules a separate job for Google Place API lookups
  defp schedule_place_lookup(venue) do
    # Create a job with the venue ID
    %{"venue_id" => venue.id}
    |> GooglePlaceLookupJob.new()
    |> Oban.insert()
  end
end

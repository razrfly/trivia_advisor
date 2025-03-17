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

              # Format event data for EventStore
              day_of_week = 1  # Monday
              start_time = "19:00"
              day_name = "Monday"

              # Create the event data map with string keys
              event_data = %{
                "raw_title" => "#{source.name} at #{venue.name}",
                "name" => venue.name,
                "time_text" => "#{day_name} #{start_time}",
                "description" => details.description || "",
                "fee_text" => "",
                "source_url" => venue_data["url"],
                "hero_image_url" => venue_data["image_url"] || "",
                "day_of_week" => day_of_week,
                "start_time" => start_time,
                "frequency" => :weekly
              }

              # Process event through EventStore
              Logger.info("🔄 Creating event for venue: #{venue.name}")

              result = EventStore.process_event(venue, event_data, source.id)
              Logger.debug("🔍 Raw result from EventStore.process_event: #{inspect(result)}")

              case result do
                {:ok, event} ->
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
                    "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                  }

                  # Update job metadata
                  query = from(job in "oban_jobs", where: job.id == type(^job_id, :integer))
                  Repo.update_all(query, set: [meta: metadata])

                  # Log success
                  Logger.info("✅ Successfully processed venue and event for #{venue.name}")
                  {:ok, metadata}

                other ->
                  Logger.error("❌ Failed to create event: #{inspect(other)}")
                  {:error, "Failed to create event: #{inspect(other)}"}
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

  # Schedules a separate job for Google Place API lookups
  defp schedule_place_lookup(venue) do
    # Create a job with the venue ID
    %{"venue_id" => venue.id}
    |> PubquizPlaceLookupJob.new()
    |> Oban.insert()
  end

  # Helper to extract entry fee from details
end

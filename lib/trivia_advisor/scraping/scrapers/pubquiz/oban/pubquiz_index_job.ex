defmodule TriviaAdvisor.Scraping.Oban.PubquizIndexJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    unique: [period: 86400] # Run once per day

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Common
  alias TriviaAdvisor.Scraping.Oban.PubquizDetailJob
  alias TriviaAdvisor.Scraping.RateLimiter

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    Logger.info("🔄 Starting Pubquiz Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")
    Logger.info("🔍 Job args: #{inspect(args)}")
    Logger.info("🔍 Limit parameter: #{inspect(limit)}")

    # Get the Pubquiz source
    source = Repo.get_by!(Source, name: "pubquiz")

    try do
      # Fetch city list and venues
      with {:ok, cities} <- Common.fetch_cities(),
           venues <- Common.fetch_venues_from_cities(cities),
           venues <- List.flatten(venues) do

        venues_count = length(venues)
        Logger.info("📊 Found #{venues_count} venues from pubquiz.pl")
        Logger.info("🔍 First venue sample: #{inspect(Enum.at(venues, 0))}")

        # Apply limit if specified
        venues_to_process = if limit, do: Enum.take(venues, limit), else: venues
        limited_count = length(venues_to_process)

        Logger.info("🔍 Venues to process count: #{limited_count}")
        if limited_count > 0 do
          Logger.info("🔍 First venue to process: #{inspect(Enum.at(venues_to_process, 0))}")
        end

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{venues_count} total)")
        end

        # Schedule detail jobs using RateLimiter
        Logger.info("🔄 Calling RateLimiter.schedule_hourly_capped_jobs with #{length(venues_to_process)} venues")

        enqueued_count = RateLimiter.schedule_hourly_capped_jobs(
          venues_to_process,
          PubquizDetailJob,
          fn venue ->
            Logger.debug("🔄 Creating job for venue: #{inspect(venue["name"])}")
            %{
              venue_data: venue,
              source_id: source.id
            }
          end
        )

        Logger.info("📥 Enqueued #{enqueued_count} PubquizDetail jobs with rate limiting")

        # Create metadata for reporting
        metadata = %{
          "total_venues" => venues_count,
          "limited_to" => limited_count,
          "applied_limit" => limit,
          "enqueued_jobs" => enqueued_count,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Update job metadata
        Repo.update_all(
          from(j in "oban_jobs", where: j.id == ^job_id),
          set: [meta: metadata]
        )

        {:ok, %{venue_count: venues_count, limited_to: limited_count, enqueued_jobs: enqueued_count}}
      else
        error ->
          Logger.error("❌ Failed to fetch venues: #{inspect(error)}")
          {:error, error}
      end
    rescue
      e ->
        Logger.error("❌ Scraper failed: #{Exception.message(e)}")
        {:error, e}
    end
  end
end

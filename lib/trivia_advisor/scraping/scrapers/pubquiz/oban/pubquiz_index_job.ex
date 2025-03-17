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
  def perform(%Oban.Job{args: _args, id: job_id}) do
    Logger.info("🔄 Starting Pubquiz Index Job...")

    # Get the Pubquiz source
    source = Repo.get_by!(Source, name: "pubquiz")

    try do
      # Fetch city list and venues
      with {:ok, cities} <- Common.fetch_cities(),
           venues <- Common.fetch_venues_from_cities(cities),
           venues <- List.flatten(venues) do

        venues_count = length(venues)
        Logger.info("📊 Found #{venues_count} venues from pubquiz.pl")

        # Schedule detail jobs using RateLimiter
        RateLimiter.schedule_hourly_capped_jobs(
          venues,
          PubquizDetailJob,
          fn venue ->
            %{
              venue_data: venue,
              source_id: source.id
            }
          end
        )

        # Create metadata for reporting
        metadata = %{
          "total_venues" => venues_count,
          "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Update job metadata
        Repo.update_all(
          from(j in "oban_jobs", where: j.id == ^job_id),
          set: [meta: metadata]
        )

        {:ok, %{venue_count: venues_count}}
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

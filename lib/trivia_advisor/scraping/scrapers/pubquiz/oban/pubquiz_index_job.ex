defmodule TriviaAdvisor.Scraping.Oban.PubquizIndexJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    unique: [period: 86400] # Run once per day

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor
  alias TriviaAdvisor.Scraping.Oban.PubquizDetailJob

  @base_url "https://pubquiz.pl/bilety/"
  @max_jobs_per_batch 10  # Process venues in batches

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args, id: job_id}) do
    Logger.info("🔄 Starting Pubquiz Index Job...")

    # Get the Pubquiz source
    source = Repo.get_by!(Source, name: "pubquiz")

    try do
      # Fetch city list and venues
      with {:ok, cities} <- fetch_cities(),
           venues <- fetch_venues_from_cities(cities),
           venues <- List.flatten(venues) do

        venues_count = length(venues)
        Logger.info("📊 Found #{venues_count} venues from pubquiz.pl")

        # Schedule detail jobs immediately
        venues
        |> Enum.each(fn venue ->
          # Create job with no scheduled_at to run immediately
          %{
            venue_data: venue,
            source_id: source.id
          }
          |> PubquizDetailJob.new()
          |> Oban.insert()
        end)

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

  defp fetch_cities do
    case HTTPoison.get(@base_url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        cities = Extractor.extract_cities(body)
        {:ok, cities}

      {:ok, %{status_code: status}} ->
        Logger.error("Failed to fetch cities. Status: #{status}")
        {:error, :http_error}

      {:error, error} ->
        Logger.error("Failed to fetch cities: #{inspect(error)}")
        {:error, error}
    end
  end

  defp fetch_venues_from_cities(cities) do
    cities
    |> Enum.map(fn city_url ->
      case HTTPoison.get(city_url, [], follow_redirect: true) do
        {:ok, %{status_code: 200, body: body}} ->
          Extractor.extract_venues(body)

        {:ok, %{status_code: status}} ->
          Logger.error("Failed to fetch venues for #{city_url}. Status: #{status}")
          []

        {:error, error} ->
          Logger.error("Failed to fetch venues for #{city_url}: #{inspect(error)}")
          []
      end
    end)
  end
end

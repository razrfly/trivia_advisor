defmodule TriviaAdvisor.Scraping.Oban.PubquizDetailJobNew do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor

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

          # Create metadata for reporting
          metadata = %{
            "venue_name" => venue_data["name"],
            "venue_url" => venue_data["url"],
            "address" => details.address,
            "phone" => details.phone,
            "host" => details.host,
            "description" => details.description,
            "source_name" => source.name,
            "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }

          # Update job metadata
          query = from(job in "oban_jobs", where: job.id == type(^job_id, :integer))
          Repo.update_all(query, set: [meta: metadata])

          # Log the details
          Logger.info("""
          ✅ Venue details:
          Name: #{venue_data["name"]}
          URL: #{venue_data["url"]}
          Address: #{details.address || "N/A"}
          Phone: #{details.phone || "N/A"}
          Host: #{details.host || "N/A"}
          Description: #{String.slice(details.description || "", 0..100)}...
          """)

          {:ok, metadata}

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
        {:error, error_msg}
    end
  end
end

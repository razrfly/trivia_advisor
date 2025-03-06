defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob do
  use Oban.Worker, queue: :default

  require Logger

  # Aliases for the Quizmeisters scraper functionality
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting Quizmeisters Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Get the Quizmeisters source
    source = Repo.get_by!(Source, website_url: "https://quizmeisters.com")

    # Call the existing fetch_venues function to get the venue list
    case fetch_venues() do
      {:ok, venues} ->
        # Log the number of venues found
        venue_count = length(venues)
        Logger.info("✅ Successfully fetched #{venue_count} venues from Quizmeisters")

        # Apply limit if specified
        venues_to_process = if limit, do: Enum.take(venues, limit), else: venues
        limited_count = length(venues_to_process)

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{venue_count} total)")
        end

        # Enqueue detail jobs for each venue
        enqueued_count = enqueue_detail_jobs(venues_to_process, source.id)
        Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing")

        # Return success with venue count
        {:ok, %{venue_count: venue_count, enqueued_jobs: enqueued_count, source_id: source.id}}

      {:error, reason} ->
        # Log the error
        Logger.error("❌ Failed to fetch Quizmeisters venues: #{inspect(reason)}")

        # Return the error
        {:error, reason}
    end
  end

  # Enqueue detail jobs for each venue
  defp enqueue_detail_jobs(venues, source_id) do
    Logger.info("🔄 Enqueueing detail jobs for #{length(venues)} venues...")

    # For each venue, create a detail job
    Enum.reduce(venues, 0, fn venue, count ->
      # Create a job with the venue data and source ID
      %{
        venue: venue,
        source_id: source_id
      }
      |> TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> count + 1
        {:error, error} ->
          Logger.error("❌ Failed to enqueue detail job for venue: #{inspect(error)}")
          count
      end
    end)
  end

  # The following function is copied from the existing Quizmeisters scraper
  # to avoid modifying the original code
  defp fetch_venues do
    api_url = "https://storerocket.io/api/user/kDJ3BbK4mn/locations"

    case HTTPoison.get(api_url) do
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
end

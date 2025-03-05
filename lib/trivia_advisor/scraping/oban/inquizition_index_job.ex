defmodule TriviaAdvisor.Scraping.Oban.InquizitionIndexJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting Inquizition Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Get the Inquizition source
    source = Repo.get_by!(Source, name: "inquizition")

    # Call the existing scraper function - we don't modify this
    results = Scraper.scrape()

    # Count total venues found
    total_venues = length(results)
    Logger.info("📊 Found #{total_venues} total venues from Inquizition")

    # Limit venues if needed (for testing)
    venues_to_process = if limit, do: Enum.take(results, limit), else: results

    # For each venue, check if we need to process it
    detail_jobs = venues_to_process
    |> Enum.filter(&filter_existing_venues/1)
    |> enqueue_detail_jobs(source.id)

    Logger.info("📥 Enqueued #{length(detail_jobs)} Inquizition detail jobs")

    {:ok, %{
      venue_count: total_venues,
      enqueued_jobs: length(detail_jobs)
    }}
  end

  # Filter out venues that already exist in our database
  defp filter_existing_venues([ok: venue]) do
    # Check if the venue address already exists in our database
    case Repo.get_by(Venue, address: venue.address) do
      nil ->
        # Venue doesn't exist, so we should process it
        Logger.info("🆕 New venue found: #{venue.name} - #{venue.address}")
        true
      _existing ->
        # Venue already exists, skip it
        Logger.info("⏩ Skipping existing venue: #{venue.name} - #{venue.address}")
        false
    end
  end
  defp filter_existing_venues(_), do: false

  # Enqueue detail jobs for venues that need processing
  defp enqueue_detail_jobs(venues_to_process, source_id) do
    Enum.map(venues_to_process, fn [ok: venue] ->
      # Find time_text from the venue data if available
      time_text = Map.get(venue, :time_text)

      # Extract only what we need for the detail job
      venue_data = %{
        "name" => venue.name,
        "address" => venue.address,
        "phone" => venue.phone,
        "website" => venue.website,
        "source_id" => source_id,
        "time_text" => time_text
      }

      # Create job from venue data
      job_result = InquizitionDetailJob.new(%{
        "venue_data" => venue_data
      })

      # Handle all possible job creation results
      job = case job_result do
        {:ok, job} -> job
        %Ecto.Changeset{valid?: true} = changeset -> changeset
        other ->
          Logger.error("❌ Unexpected job creation result for venue #{venue.name}: #{inspect(other)}")
          nil
      end

      # Insert the job if we got a valid job or changeset
      if job do
        Logger.info("📥 Enqueuing detail job for venue: #{venue.name}")

        # Insert the job
        case Oban.insert(job) do
          {:ok, _oban_job} ->
            Logger.info("✓ Job successfully inserted for venue: #{venue.name}")
            venue.name
          {:error, error} ->
            Logger.error("❌ Failed to insert job for venue #{venue.name}: #{inspect(error)}")
            nil
          other ->
            Logger.error("❌ Unexpected result when inserting job for venue #{venue.name}: #{inspect(other)}")
            nil
        end
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end

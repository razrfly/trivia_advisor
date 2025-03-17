require Logger

# Start required services (handle already started case)
Logger.info("Starting GooglePlacesService")
case TriviaAdvisor.Services.GooglePlacesService.start_link([]) do
  {:ok, _} -> Logger.info("GooglePlacesService started")
  {:error, {:already_started, _}} -> Logger.info("GooglePlacesService already running")
  error -> Logger.error("Failed to start GooglePlacesService: #{inspect(error)}")
end

Logger.info("Starting GooglePlaceImageStore")
case TriviaAdvisor.Services.GooglePlaceImageStore.start_link([]) do
  {:ok, _} -> Logger.info("GooglePlaceImageStore started")
  {:error, {:already_started, _}} -> Logger.info("GooglePlaceImageStore already running")
  error -> Logger.error("Failed to start GooglePlaceImageStore: #{inspect(error)}")
end

# Get the pubquiz source
source = TriviaAdvisor.Repo.get_by!(TriviaAdvisor.Scraping.Source, name: "pubquiz")
Logger.info("Using source: #{source.name} (ID: #{source.id})")

# Generate a unique venue name
venue_name = "Test Venue #{:rand.uniform(10000)}"

# Create job args
job_args = %{
  "venue_data" => %{
    "name" => venue_name,
    "url" => "https://pubquiz.pl/kategoria-produktu/bydgoszcz/cybermachina-bydgoszcz/", # Using a known working URL
    "address" => "Test Address, Poland"
  },
  "source_id" => source.id
}

Logger.info("Creating PubquizDetailJob for venue: #{venue_name}")
{:ok, job} = TriviaAdvisor.Scraping.Oban.PubquizDetailJob.new(job_args) |> Oban.insert()
Logger.info("Created job with ID: #{job.id}")

# Wait for job completion
Logger.info("Waiting for job to complete...")
max_wait = 30 # seconds
wait_interval = 2 # seconds
complete = false

Enum.reduce_while(1..div(max_wait, wait_interval), nil, fn _, _ ->
  Process.sleep(wait_interval * 1000)

  updated_job = TriviaAdvisor.Repo.get(Oban.Job, job.id)

  cond do
    updated_job.state == "completed" ->
      Logger.info("✅ Job completed successfully")
      {:halt, updated_job}

    updated_job.state == "discarded" || updated_job.state == "cancelled" ->
      Logger.error("❌ Job failed: #{updated_job.state}")
      Logger.error("Error: #{inspect(updated_job.errors)}")
      {:halt, updated_job}

    true ->
      Logger.info("⏳ Job still running (state: #{updated_job.state})...")
      {:cont, nil}
  end
end)
|> case do
  %Oban.Job{state: "completed"} = completed_job ->
    Logger.info("Job metadata: #{inspect(completed_job.meta)}")

    if completed_job.meta["event_id"] do
      event_id = completed_job.meta["event_id"]
      event = TriviaAdvisor.Events.Event |> TriviaAdvisor.Repo.get(event_id)

      Logger.info("Created event details:")
      Logger.info("  ID: #{event.id}")
      Logger.info("  Name: #{event.name}")
      Logger.info("  Day: #{event.day_of_week}")
      Logger.info("  Time: #{event.start_time}")
      Logger.info("  Fee: #{event.entry_fee_cents} cents")

      # Check if fee is correctly set
      if event.entry_fee_cents > 0 do
        Logger.info("✅ SUCCESS: Fee set correctly to #{event.entry_fee_cents} cents")
      else
        Logger.error("❌ FAILURE: Fee is zero or not set")
      end

      # Get the event source
      source_record = TriviaAdvisor.Events.EventSource
        |> TriviaAdvisor.Repo.get_by(event_id: event.id)

      if source_record do
        Logger.info("Event source metadata:")
        Logger.info("  Fee text: #{source_record.metadata["fee_text"]}")
      end
    else
      Logger.error("❌ No event_id found in job metadata")
    end

  nil ->
    Logger.error("❌ Job didn't complete within the expected time")

  job ->
    Logger.error("❌ Job failed with state: #{job.state}")
    Logger.error("Error: #{inspect(job.errors)}")
end

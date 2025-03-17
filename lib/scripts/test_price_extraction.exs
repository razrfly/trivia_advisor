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

# Create a test venue
venue_attrs = %{
  name: "Test Venue #{:rand.uniform(1000)}",
  address: "Test Address, Warsaw, Poland",
  phone: "+48123456789",
  website: "https://example.com/test",
  skip_image_processing: true
}

Logger.info("Creating test venue: #{venue_attrs.name}")
{:ok, venue} = TriviaAdvisor.Locations.VenueStore.process_venue(venue_attrs)
Logger.info("Created venue with ID: #{venue.id}")

# Ensure venue is properly preloaded
venue = TriviaAdvisor.Repo.preload(venue, [city: :country])

# Test different fee_text formats
test_cases = [
  {"15.0", 1500},
  {"15.0 zł", nil},  # This will likely fail with the original EventStore
  {"15,0 zł", nil},  # This will likely fail with the original EventStore
  {"15.00", 1500},
  {"15", 1500}
]

Logger.info("Testing different fee text formats...")

Enum.each(test_cases, fn {fee_text, expected_cents} ->
  Logger.info("\n---\nTesting fee text: '#{fee_text}'")

  # Create event data
  event_data = %{
    "raw_title" => "Test Quiz at #{venue.name}",
    "name" => "Test Quiz at #{venue.name}",
    "time_text" => "Tuesday 20:00",
    "description" => "A test quiz event",
    "fee_text" => fee_text,
    "source_url" => "https://example.com/test",
    "hero_image_url" => "",
    "day_of_week" => 2,
    "start_time" => ~T[20:00:00],
    "frequency" => :weekly
  }

  # Process the event
  result = TriviaAdvisor.Events.EventStore.process_event(venue, event_data, source.id)

  case result do
    {:ok, {:ok, event}} ->
      Logger.info("Created event with ID: #{event.id}")
      Logger.info("Fee text: #{fee_text} -> Stored fee: #{event.entry_fee_cents} cents")

      # Check if fee is as expected
      if expected_cents == nil do
        Logger.info("ℹ️ Fee value was not predicted - got #{event.entry_fee_cents} cents")
      else
        if event.entry_fee_cents == expected_cents do
          Logger.info("✅ SUCCESS: Fee stored correctly")
        else
          Logger.info("ℹ️ DIFFERENT: Expected #{expected_cents} cents, got #{event.entry_fee_cents} cents")
        end
      end

    _ ->
      Logger.error("❌ Failed to create event with fee text: #{fee_text}")
  end
end)

# Now manually test a pubquiz job to see what fee text it generates
Logger.info("\n---\nNow testing the actual Pubquiz detail job")

# Use the test URL from the pubquiz index job
test_url = "https://pubquiz.pl/kategoria-produktu/warszawa/hard-rock-cafe/"

# Create a job
job_args = %{
  "venue_data" => %{
    "name" => "Hard Rock Cafe",
    "url" => test_url,
  },
  "source_id" => source.id
}

Logger.info("Creating PubquizDetailJob for #{test_url}")
{:ok, job} = TriviaAdvisor.Scraping.Oban.PubquizDetailJob.new(job_args) |> Oban.insert()
Logger.info("Created job with ID: #{job.id}")

# Give it some time to run
Logger.info("Waiting 10 seconds for job to complete...")
Process.sleep(10000)

# Check the job status
updated_job = TriviaAdvisor.Repo.get(Oban.Job, job.id)
Logger.info("Job state: #{updated_job.state}")

if updated_job.state == "completed" do
  Logger.info("Job metadata: #{inspect(updated_job.meta)}")
  Logger.info("Entry fee cents from job: #{updated_job.meta["entry_fee_cents"]}")

  # Check the created event
  if updated_job.meta["event_id"] do
    event_id = updated_job.meta["event_id"]
    event = TriviaAdvisor.Events.Event |> TriviaAdvisor.Repo.get(event_id)

    Logger.info("Created event ID: #{event.id}")
    Logger.info("Event name: #{event.name}")
    Logger.info("Event day: #{event.day_of_week}")
    Logger.info("Event fee: #{event.entry_fee_cents} cents")

    # Get the event source
    source_record = TriviaAdvisor.Events.EventSource
      |> TriviaAdvisor.Repo.get_by(event_id: event.id)

    if source_record do
      Logger.info("Event source metadata: #{inspect(source_record.metadata)}")
    end
  end
else
  Logger.error("Job did not complete successfully")
end

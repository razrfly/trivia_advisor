# TriviaAdvisor

TriviaAdvisor helps you find and track pub quiz nights and trivia events in your area. Think of it as a "Yelp for pub quizzes" - helping trivia enthusiasts discover new venues and keep track of their favorite quiz nights.

## Repository Information

- **GitHub Repository**: [holden/trivia_advisor](https://github.com/holden/trivia_advisor)
- **Note**: This project uses an underscore in its name (`trivia_advisor`), not a hyphen.

## Features

- 🎯 Find trivia nights near you
- 📅 Track recurring events by venue
- 🌐 Aggregates data from multiple trivia providers
- 🗺️ Map integration for easy venue discovery
- 📱 Mobile-friendly interface

## Scraper Design Pattern

### 🏗️ File Structure
```
lib/trivia_advisor/scraping/scrapers/[source_name]/
├── scraper.ex          # Main scraper module
└── venue_extractor.ex  # HTML extraction logic
```

### 🔄 Main Scraper Flow
```elixir
# 1. Index Job to fetch venue list
def perform(%Oban.Job{id: job_id}) do
  # Question One: RSS feed pagination
  # Inquizition: API endpoint
  venues = fetch_venues()

  # 2. Process venues by scheduling detail jobs
  total_venues = length(venues)
  processed_venues = schedule_detail_jobs(venues)

  # 3. Update Job Metadata
  JobMetadata.update_index_job(job_id, %{
    total_venues: total_venues,
    enqueued_jobs: processed_venues,
    metadata: %{
      started_at: start_time,
      completed_at: DateTime.utc_now()
    }
  })
  
  :ok
end
```

### 🏢 Venue Processing Steps
```elixir
# 1. Extract Basic Venue Data
venue_data = %{
  name: extracted_data.title,
  address: extracted_data.address,
  phone: extracted_data.phone,
  website: extracted_data.website
}

# 2. Process Through VenueStore
{:ok, venue} = VenueStore.process_venue(venue_data)
# This handles:
# - Google Places API lookup
# - Country/City creation
# - Venue creation/update

# 3. Process Event
event_data = %{
  name: "#{source.name} at #{venue.name}",
  venue_id: venue.id,
  day_of_week: day,
  start_time: time,
  frequency: frequency,
  description: description,
  entry_fee_cents: parse_currency(fee_text)
}

# 4. Create/Update Event
{:ok, event} = EventStore.process_event(venue, event_data, source.id)
```

### ⚠️ Error Handling Pattern
```elixir
# 1. Top-level Job error handling
def perform(%Oban.Job{id: job_id}) do
  try do
    # Main scraping logic
    :ok
  rescue
    e ->
      JobMetadata.update_error(job_id, Exception.format(:error, e, __STACKTRACE__))
      Logger.error("Scraper failed: #{Exception.message(e)}")
      {:error, e}
  end
end

# 2. Individual venue rescue
try do
  # Venue processing
rescue
  e ->
    Logger.error("Failed to process venue: #{inspect(e)}")
    nil  # Skip this venue but continue with others
end
```

### 📝 Logging Standards
```elixir
# 1. Start of scrape
Logger.info("Starting #{source.name} scraper")

# 2. Venue count
Logger.info("Found #{venue_count} venues")

# 3. Individual venue processing
Logger.info("Processing venue: #{venue.name}")

# 4. VenueHelpers.log_venue_details for consistent format
VenueHelpers.log_venue_details(%{
  raw_title: raw_title,
  title: clean_title,
  address: address,
  time_text: time_text,
  day_of_week: day_of_week,
  start_time: start_time,
  frequency: frequency,
  fee_text: fee_text,
  phone: phone,
  website: website,
  description: description,
  hero_image_url: hero_image_url,
  url: source_url
})
```

### ✅ Data Validation Requirements
1. Venue must have:
   - Valid name
   - Valid address
   - Day of week
   - Start time

2. Event must have:
   - Valid venue_id
   - Valid day_of_week
   - Valid start_time
   - Valid frequency

### 🗄️ Database Operations Order
1. Country (find or create)
2. City (find or create, linked to country)
3. Venue (find or create, linked to city)
4. Event (find or create, linked to venue)
5. EventSource (find or create, linked to event and source)

## Oban Job Design Pattern

### 🔄 Index and Detail Job Structure
```
lib/trivia_advisor/scraping/oban/[source_name]_index_job.ex   # Lists venues and schedules detail jobs
lib/trivia_advisor/scraping/oban/[source_name]_detail_job.ex  # Processes individual venues/events
```

### 📊 Metadata Handling
All scrapers should use the centralized `JobMetadata` module for updating job metadata:

```elixir
# In detail jobs:
def perform(%Oban.Job{args: args, id: job_id}) do
  # Process the venue and event
  result = process_venue(args["venue_data"], source)
  
  # Handle the result and update metadata
  handle_processing_result(result, job_id, source)
end

# Handle the processing result uniformly
defp handle_processing_result(result, job_id, source) do
  case result do
    {:ok, %{venue: venue, event: event}} ->
      # Update metadata with the JobMetadata helper
      metadata = %{
        "venue_name" => venue.name,
        "venue_id" => venue.id,
        "event_id" => event.id,
        # Additional fields...
      }
      
      JobMetadata.update_detail_job(job_id, metadata, %{venue_id: venue.id, event_id: event.id})
      
      {:ok, %{venue_id: venue.id, event_id: event.id}}
      
    {:error, reason} ->
      # Update error metadata
      JobMetadata.update_error(job_id, reason)
      {:error, reason}
  end
end
```

### 🖼️ Image Handling Pattern
For consistently handling venue/event images:

```elixir
# Download and attach hero images for events
hero_image_url = venue_data["image_url"]
if hero_image_url && hero_image_url != "" do
  # Pass force_refresh_images flag to control image refresh
  force_refresh_images = Process.get(:force_refresh_images, false)
  case ImageDownloader.download_event_hero_image(hero_image_url, force_refresh_images) do
    {:ok, upload} ->
      Logger.info("✅ Successfully downloaded hero image")
      Map.put(event_data, :hero_image, upload)
    {:error, reason} ->
      Logger.warning("⚠️ Failed to download hero image: #{inspect(reason)}")
      event_data
  end
else
  event_data
end
```

### 🔄 Force Refresh Images
All scrapers support the `force_refresh_images` flag that ensures images are always fresh:

1. **How It Works**:
   - When enabled, existing images are deleted before downloading new ones
   - Bypasses image caching in ImageDownloader
   - Propagates through the entire process from index job to detail job to EventStore
   
2. **Usage in Jobs**:
```elixir
# Through Oban job args
{:ok, _job} = Oban.insert(
  TriviaAdvisor.Scraping.Oban.PubquizIndexJob.new(%{
    "force_refresh_images" => true,
    "limit" => 5
  })
)

# Through mix task flags
mix scraper.test_pubquiz_index --limit=3 --force-refresh-images
```

3. **Implementation**:
   - Index job passes flag to detail jobs
   - Detail job sets Process.put(:force_refresh_images, true)
   - ImageDownloader checks flag to force redownload
   - EventStore explicitly deletes existing images when flag is true
   
4. **Supported Scrapers**:
   - Question One
   - Quizmeisters
   - Geeks Who Drink
   - PubQuiz

### ⚠️ Important Notes
1. NEVER make DB migrations without asking first
2. Always follow the existing pattern for consistency
3. Maintain comprehensive logging
4. Handle errors gracefully
5. Use the VenueHelpers module for common functionality
6. NEVER write repetitive case statements that do the same thing with different data structures - see [Scraping Best Practices](lib/trivia_advisor/scraping/README.md#best-practices) for details
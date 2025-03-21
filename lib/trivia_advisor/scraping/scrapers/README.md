# TriviaAdvisor Scraper Specification

This document provides a comprehensive specification for implementing scrapers in the TriviaAdvisor application. It covers the architectural patterns, design considerations, and best practices learned from implementing the existing scrapers (Question One, Inquizition, Geeks Who Drink, Speed Quizzing, and Quizmeisters).

## Table of Contents

1. [Scraper Architecture](#scraper-architecture)
2. [File Structure](#file-structure)
3. [Scraper Implementation Workflow](#scraper-implementation-workflow)
4. [Google API Integration](#google-api-integration)
5. [Error Handling](#error-handling)
6. [Logging Standards](#logging-standards)
7. [Data Validation](#data-validation)
8. [Rate Limiting](#rate-limiting)
9. [Common Helpers](#common-helpers)
10. [Image Handling](#image-handling)
11. [Testing](#testing)

## Dependencies

The following dependencies are already set up and available for all scrapers:

- HTTPoison - HTTP client for making requests
- Floki - HTML parsing
- Oban - Background job processing
- Jason - JSON encoding/decoding
- Tesla - HTTP client with middleware support (for API integrations)

No additional dependencies need to be added for new scrapers unless they have very specific requirements.

## Scraper Architecture

All TriviaAdvisor scrapers follow a two-tier Oban job architecture:

1. **Index Job**: Responsible for fetching lists of venues/events
   - Processes source websites to identify venue/event listings
   - Schedules individual Detail Jobs for each venue/event
   - Rate-limits Detail Job execution to prevent system overload
   - Records scrape logs for monitoring and debugging

2. **Detail Job**: Responsible for processing individual venues/events
   - Extracts detailed information for a single venue/event
   - Interacts with VenueStore/EventStore to persist data
   - Handles Google APIs for geocoding and place information
   - Processes images and additional metadata

This separation allows for robust error handling, effective rate limiting, and independent processing of each venue without affecting others.

## File Structure

Each scraper should maintain the following file structure:

```
lib/trivia_advisor/scraping/scrapers/[source_name]/
├── scraper.ex                # Main module with shared functions (legacy)
├── extractor.ex              # HTML/data extraction logic (optional)
├── oban/
│   ├── [source]_index_job.ex # Index job implementation
│   └── [source]_detail_job.ex # Detail job implementation
```

For new scrapers, focus on implementing just the Oban job files.

## Scraper Implementation Workflow

### 1. Index Job Implementation

The Index Job follows this pattern:

```elixir
defmodule TriviaAdvisor.Scraping.Oban.[SourceName]IndexJob do
  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    unique: [period: 86400] # Run once per day

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.{Source, ScrapeLog, RateLimiter}
  alias TriviaAdvisor.Scraping.Oban.[SourceName]DetailJob
  
  @base_url "https://example.com/venues"

  @impl Oban.Worker
  def perform(_job) do
    # 1. Initialize Scrape Log
    source = Repo.get_by!(Source, name: "source_name")
    {:ok, log} = ScrapeLog.create_log(source)
    start_time = DateTime.utc_now()

    try do
      # 2. Fetch venue list
      venues = fetch_venues()
      venues_count = length(venues)
      Logger.info("Found #{venues_count} venues")

      # 3. Schedule Detail Jobs with rate limiting
      RateLimiter.schedule_hourly_capped_jobs(
        venues,
        [SourceName]DetailJob,
        fn venue -> 
          %{
            venue_id: venue.id,
            venue_data: venue,
            log_id: log.id,
            source_id: source.id
          }
        end
      )

      # 4. Update Scrape Log with success
      ScrapeLog.update_log(log, %{
        success: true,
        total_venues: venues_count,
        metadata: %{
          started_at: start_time,
          completed_at: DateTime.utc_now()
        }
      })

      {:ok, %{venues_count: venues_count}}
    rescue
      e ->
        # Log error and update scrape log
        Logger.error("Scraper failed: #{Exception.message(e)}")
        ScrapeLog.log_error(log, e)
        {:error, e}
    end
  end

  # Implement source-specific venue fetching
  defp fetch_venues do
    # Implementation depends on source
  end
end
```

### 2. Detail Job Implementation

The Detail Job follows this pattern:

```elixir
defmodule TriviaAdvisor.Scraping.Oban.[SourceName]DetailJob do
  use Oban.Worker,
    queue: :venue_processor,
    max_attempts: 3

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Scraping.{ScrapeLog, Source, Helpers.VenueHelpers}
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    venue_data = args["venue_data"]
    log_id = args["log_id"]
    source_id = args["source_id"]
    
    # Get source record
    source = Repo.get(Source, source_id)
    
    try do
      # 1. Process venue details
      venue_attrs = %{
        name: venue_data["name"],
        address: venue_data["address"],
        phone: venue_data["phone"],
        website: venue_data["website"]
      }
      
      # 2. Process venue through VenueStore
      case VenueStore.process_venue(venue_attrs) do
        {:ok, venue} ->
          # Optionally update Google Place images
          venue = GooglePlaceImageStore.maybe_update_venue_images(venue)
          
          # 3. Process event data
          event_attrs = %{
            name: "#{source.name} at #{venue.name}",
            venue_id: venue.id,
            day_of_week: venue_data["day_of_week"],
            start_time: venue_data["start_time"],
            frequency: venue_data["frequency"] || "weekly",
            description: venue_data["description"],
            entry_fee_cents: venue_data["entry_fee_cents"]
          }
          
          # 4. Create/update event
          case EventStore.process_event(venue, event_attrs, source.id) do
            {:ok, event} ->
              Logger.info("✅ Successfully processed event for venue: #{venue.name}")
              {:ok, %{venue_id: venue.id, event_id: event.id}}
              
            {:error, reason} ->
              Logger.error("❌ Failed to process event: #{inspect(reason)}")
              {:error, reason}
          end
          
        {:error, reason} ->
          Logger.error("❌ Failed to process venue: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("""
        ❌ Failed to process venue
        Error: #{Exception.message(e)}
        Venue Data: #{inspect(venue_data)}
        """)
        
        if log_id, do: ScrapeLog.log_venue_error(log_id, venue_data, e)
        {:error, e}
    end
  end
end
```

## Google API Integration

### Current Flow

1. **VenueStore.process_venue** is the entry point for Google API operations
2. The function first checks for existing venues with coordinates
3. For new venues or venues without coordinates, it schedules a GoogleLookupJob
4. GoogleLookupJob handles:
   - Place API lookups
   - Geocoding API fallbacks
   - Image retrieval using GooglePlaceImageStore
5. Once coordinates are stored, they're never looked up again

### Optimized Flow (For New Scrapers)

For new scrapers, implement the following enhanced pattern which separates Place API calls into a dedicated queue:

1. Continue to use **VenueStore.process_venue** as the primary entry point
2. After successful venue creation, schedule a separate job for Google Place lookups:
   ```elixir
   # Schedule a GooglePlaceLookupJob to handle Google Places API operations
   defp schedule_place_lookup(venue) do
     %{"venue_id" => venue.id}
     |> TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob.new()
     |> Oban.insert()
   end
   ```
3. Use an optional flag to explicitly request or skip image processing at the VenueStore level:
   ```elixir
   # Skip image processing entirely for batch jobs
   venue_attrs = Map.put(venue_attrs, :skip_image_processing, true)
   ```

This pattern ensures that Google Places API interactions are:
- Isolated in a dedicated job for better monitoring
- Rate-limited independently from other operations
- More easily maintained across all scrapers

## Error Handling

All scrapers should implement the following error handling pattern:

1. **Top-level rescue** in the perform function:
   ```elixir
   try do
     # Main scraping logic
   rescue
     e ->
       ScrapeLog.log_error(log, e)
       Logger.error("Scraper failed: #{Exception.message(e)}")
       {:error, e}
   end
   ```

2. **Individual venue rescue** in processing functions:
   ```elixir
   try do
     # Venue processing logic
   rescue
     e ->
       Logger.error("Failed to process venue: #{inspect(e)}")
       nil  # Skip this venue but continue with others
   end
   ```

3. **Error handling in API calls**:
   - Always handle API timeouts and HTTP errors
   - Use pattern matching for error responses
   - Log detailed error information
   - Implement appropriate retries (handled by Oban)

## Logging Standards

Follow these logging standards for all scrapers:

1. **Start of scrape**:
   ```elixir
   Logger.info("Starting #{source.name} scraper")
   ```

2. **Venue count**:
   ```elixir
   Logger.info("Found #{venue_count} venues")
   ```

3. **Individual venue processing**:
   ```elixir
   Logger.info("Processing venue: #{venue.name}")
   ```

4. **Consistent venue details logging using VenueHelpers**:
   ```elixir
   VenueHelpers.log_venue_details(%{
     raw_title: raw_title,
     title: clean_title,
     address: address,
     time_text: time_text,
     day_of_week: day_of_week,
     start_time: start_time,
     # More fields...
   })
   ```

5. **Success/failure logging**:
   ```elixir
   Logger.info("✅ Successfully processed venue: #{venue.name}")
   Logger.error("❌ Failed to process venue: #{inspect(reason)}")
   ```

## Data Validation

Enforce these validation requirements for all data:

1. **Venue Validation**:
   - Valid name (required)
   - Valid address (required)
   - Day of week (required)
   - Start time (required)

2. **Event Validation**:
   - Valid venue_id (required)
   - Valid day_of_week (required)
   - Valid start_time (required)
   - Valid frequency (required, default to "weekly" if not specified)

3. Use Elixir's pattern matching to enforce this validation:
   ```elixir
   def process_venue(%{name: name, address: address, day_of_week: day, start_time: time} = venue_data)
     when is_binary(name) and is_binary(address) and is_binary(day) and is_binary(time) do
     # Processing logic
   end
   def process_venue(_), do: {:error, :invalid_venue_data}
   ```

## Rate Limiting

Always use the RateLimiter module to schedule jobs:

```elixir
# For smaller scrapers (< 100 venues)
RateLimiter.schedule_detail_jobs(
  venues,
  DetailJobModule,
  fn venue -> %{venue_id: venue.id} end
)

# For larger scrapers (100+ venues)
RateLimiter.schedule_hourly_capped_jobs(
  venues,
  DetailJobModule,
  fn venue -> %{venue_id: venue.id} end
)
```

This ensures:
1. Smooth system load
2. Gradual Google API usage
3. Configurable job spacing
4. Automatic job cleanup

See `lib/trivia_advisor/scraping/README.md` for more details on rate limiting.

## Common Helpers

Make use of these helper modules:

1. **VenueHelpers** - Common functions for venue data processing
2. **TimeParser** - Functions for parsing and standardizing time strings
3. **ImageDownloader** - Utilities for downloading and processing images
4. **JobMetadata** - Helpers for managing job metadata

## Image Handling

### Consistent Image Naming

All scrapers must follow these guidelines for hero image handling:

1. **Always use the centralized ImageDownloader module**:
   ```elixir
   alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
   
   # For event hero images
   case ImageDownloader.download_event_hero_image(hero_image_url) do
     {:ok, upload} -> 
       # Use the upload in your event data
       %{hero_image: upload}
     {:error, reason} ->
       Logger.warning("Failed to download hero image: #{inspect(reason)}")
       %{}
   end
   ```

2. **Never implement custom image downloading logic**:
   - ❌ Don't use `VenueHelpers.download_image` for hero images
   - ❌ Don't use HTTPoison directly for image downloading
   - ❌ Don't create custom filename generation logic
   - ✅ Always use `ImageDownloader.download_event_hero_image` for consistent behavior

3. **When to download images**:
   - Download images at the detail job level, not the venue processing level
   - Include the downloaded image in the data passed to EventStore

4. **Filename Normalization Rules**:
   All hero image filenames adhere to these rules:
   - Original filename preserved as much as possible
   - Spaces converted to dashes (-)
   - URL-encoded characters decoded and formatted properly
   - Query parameters stripped (everything after ? removed)
   - Double dashes (--) reduced to single dash
   - Consistent case handling (lowercase preferred)
   - Small hash suffix appended for uniqueness while preserving the original name
   
   IMPORTANT: Preserving original filenames is critical to prevent re-downloading 
   the same images on subsequent scrapes. The system identifies existing images by 
   filename, so custom naming schemes will cause continuous re-downloading of the 
   same images, wasting bandwidth and storage.
   
   These rules are implemented in the `ImageDownloader` module and should not be reimplemented.

### Image Processing Flow

The correct flow for handling hero images in scrapers:

1. **Extract image URL** from the source website
2. **Pass the raw URL** to `ImageDownloader.download_event_hero_image`
3. **Include the returned Plug.Upload struct** in the event attributes
4. **Pass to EventStore** which will handle storage and database references

Example implementation:
```elixir
# In your venue/event detail extraction
hero_image_url = extract_hero_image_url_from_page(html)

# Process the hero image
hero_image_attrs = if hero_image_url && hero_image_url != "" do
  case ImageDownloader.download_event_hero_image(hero_image_url) do
    {:ok, upload} ->
      %{hero_image: upload}
    {:error, _reason} ->
      %{}  # No image if download fails
  end
else
  %{}  # No image if URL is empty or nil
end

# Merge with other event attributes
event_attrs = %{
  name: "Event Name",
  day_of_week: day_of_week,
  # Other attributes...
} |> Map.merge(hero_image_attrs)

# Pass to EventStore
EventStore.process_event(venue, event_attrs, source_id)
```

This standardized approach ensures all hero images are processed consistently across all scrapers.

## Testing

Implement these testing strategies:

1. **Debug scripts** for testing scrapers:
   ```bash
   # Run a single venue test
   mix run lib/scripts/test_[source_name].exs
   ```

2. **Manual testing** through mix tasks or IEx:
   ```elixir
   # In IEx
   iex> Oban.insert(TriviaAdvisor.Scraping.Oban.ExampleDetailJob.new(%{venue_id: 123}))
   ```

3. **Limited testing with mix tasks**:
   ```bash
   # Test an index job with a limit of 3 venues
   mix scraper.test_[source_name]_index --limit=3
   ```

4. **Venue limiting in index jobs**:
   All index jobs must support a `limit` parameter in their args to restrict the number of venues processed during testing:
   ```elixir
   # In the perform function of any index job
   limit = Map.get(args, "limit")
   venues_to_process = if limit, do: Enum.take(venues, limit), else: venues
   
   # Log the limitation
   if limit do
     Logger.info("🧪 Testing mode: Limited to #{length(venues_to_process)} venues (out of #{length(venues)} total)")
   end
   ```

5. **Monitoring** through Oban dashboard or database queries:
   ```elixir
   # Query jobs by state
   Repo.all(from j in Oban.Job, where: j.queue == "venue_processor" and j.state == "executing")
   ```

---

By following this specification, all new scrapers will be consistent, reliable, and maintainable. This approach minimizes the roadblocks encountered in previous implementations and provides a clear path forward for adding new data sources. 
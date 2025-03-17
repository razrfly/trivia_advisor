# TriviaAdvisor Google API Optimization

This document outlines the implementation strategy for optimizing Google API usage in TriviaAdvisor by creating a dedicated Oban queue specifically for Google Place API calls. The goal is to better track, monitor, and control Place API usage to minimize costs while maintaining functionality.

## Current Architecture

The current implementation uses a single `google_api` queue for all Google API interactions:

1. `VenueStore.process_venue` is the entry point for new venues
2. If a venue lacks coordinates, it schedules a `GoogleLookupJob` in the `google_api` queue
3. `GoogleLookupJob` handles both geocoding (coordinates) and Place API (business details)
4. `GooglePlaceImageStore` handles image fetching and processing, also using the same queue

This setup works but has limitations:
- Difficult to differentiate between Place API and Geocoding API costs
- No fine-grained control over different API types' rate limits
- All Google API calls compete for the same queue resources

## Optimized Architecture

The proposed architecture separates concerns by using dedicated queues:

1. `google_geocoding` queue - Only for initial geocoding lookups (one-time per venue)
2. `google_places` queue - Only for Place API calls (business details and photos)

### Implementation Steps

#### 1. Update Oban Configuration

Add the new queues in your config files:

```elixir
# config/config.exs
config :trivia_advisor, Oban,
  queues: [
    default: 10,
    scraper: 5,
    venue_processor: 10,
    google_api: 3,  # existing queue
    google_geocoding: 3,  # new geocoding-specific queue
    google_places: 3  # new places-specific queue
  ]
```

#### 2. Create New Job Modules

##### GoogleGeocodingJob

```elixir
defmodule TriviaAdvisor.Scraping.Oban.GoogleGeocodingJob do
  @moduledoc """
  Handles geocoding lookups for venues.
  This job handles only coordinate lookups, not place details or images.
  """

  use Oban.Worker,
    queue: :google_geocoding,
    max_attempts: 3,
    priority: 1

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{Venue, City, Country}
  alias TriviaAdvisor.Scraping.GoogleLookup
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    venue_name = args["venue_name"]
    address = args["address"]
    existing_venue_id = args["existing_venue_id"]
    
    Logger.metadata(google_geocoding_job: true, venue_name: venue_name)
    Logger.info("🔍 Processing geocoding lookup for venue: #{venue_name}")
    
    # Check if we need to lookup the venue by ID first
    venue = if existing_venue_id, do: Repo.get(Venue, existing_venue_id), else: nil
    
    case venue do
      # If venue exists and has coordinates, just return it (skip API call)
      %Venue{latitude: lat, longitude: lng} = venue when not is_nil(lat) and not is_nil(lng) ->
        Logger.info("⏭️ Skipping geocoding API lookup - venue already has coordinates")
        {:ok, venue}
        
      # Either venue doesn't exist or doesn't have coordinates, proceed with API lookup
      _ ->
        # Check if we have coordinates in the args
        lat = args["lat"] || args["latitude"]
        lng = args["lng"] || args["longitude"]
        
        # Use direct coordinate lookup if coordinates are provided
        lookup_result = if lat && lng do
          Logger.info("🌎 Using coordinates directly: #{lat}, #{lng}")
          {:ok, build_location_data(venue_name, address, lat, lng)}
        else
          # Fall back to address lookup - GEOCODING ONLY, no places
          Logger.info("🏠 Using address lookup: #{address}")
          geocoding_only_lookup(address, venue_name)
        end
        
        # Process the lookup result (coordinates only, no place details or images)
        case lookup_result do
          {:ok, location_data} ->
            Logger.info("✅ Geocoding API lookup successful for venue: #{venue_name}")
            
            # Process the venue with just the location data (coordinates)
            process_venue_with_location(venue_name, address, location_data, args)
            
          {:error, reason} ->
            Logger.error("❌ Geocoding API lookup failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end
  
  # Specialized function that does ONLY geocoding, no places lookups
  defp geocoding_only_lookup(address, venue_name) do
    # Implementation that only calls the Geocoding API
    # Extract from existing GoogleLookup but simplify to only do geocoding
  end
  
  # Process venue with just coordinate data
  defp process_venue_with_location(venue_name, address, location_data, additional_attrs) do
    # Similar to existing process but without place details or images
    # When complete, schedule a GooglePlacesJob for business details if needed
  end
  
  # Helper to build location data from coordinates
  defp build_location_data(venue_name, address, lat, lng) do
    # Build a basic location data structure from coordinates
  end
end
```

##### GooglePlacesJob

```elixir
defmodule TriviaAdvisor.Scraping.Oban.GooglePlacesJob do
  @moduledoc """
  Handles Google Places API lookups for venue details and images.
  This job assumes coordinates are already known and focuses on business details.
  """

  use Oban.Worker,
    queue: :google_places,
    max_attempts: 3,
    priority: 1

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Services.{GooglePlacesService, GooglePlaceImageStore}
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    venue_id = args["venue_id"]
    venue = Repo.get(Venue, venue_id) |> Repo.preload([city: :country])
    
    Logger.metadata(google_places_job: true, venue_name: venue.name)
    Logger.info("🔍 Processing Google Places details for venue: #{venue.name}")
    
    # We already have coordinates, so focus on place details and images
    try do
      # Step 1: Try to find place details using existing coordinates
      place_details = if venue.latitude && venue.longitude do
        get_place_details_by_coordinates(venue.latitude, venue.longitude, venue.name)
      else
        {:error, :missing_coordinates}
      end
      
      # Step 2: Update venue with place details if found
      venue = case place_details do
        {:ok, details} -> 
          update_venue_with_place_details(venue, details)
        _ -> 
          venue
      end
      
      # Step 3: Process images (regardless of place details success)
      updated_venue = GooglePlaceImageStore.maybe_update_venue_images(venue)
      
      # Return successfully processed venue
      {:ok, updated_venue}
    rescue
      e ->
        Logger.error("❌ Failed to process Google Places details: #{Exception.message(e)}")
        {:error, e}
    end
  end
  
  # Get place details from coordinates (extracted from GoogleLookup)
  defp get_place_details_by_coordinates(lat, lng, venue_name) do
    # Implementation to lookup place by coordinates
  end
  
  # Update venue with place details
  defp update_venue_with_place_details(venue, details) do
    # Implementation to update venue with place details
  end
end
```

#### 3. Modify VenueStore.process_venue

Update the VenueStore to use the new dedicated jobs:

```elixir
def process_venue(%{address: address} = attrs) when is_binary(address) do
  # Check for existing venue with coordinates
  case find_existing_venue(attrs) do
    %{latitude: lat, longitude: lng} = existing when not is_nil(lat) and not is_nil(lng) ->
      # Skip API call entirely if we have coordinates
      Logger.info("✅ Using stored coordinates for venue: #{attrs.name}")
      
      # Optionally schedule a place details refresh if requested
      if attrs[:refresh_place_details] do
        schedule_place_details_job(existing)
      end
      
      {:ok, existing}

    existing ->
      # If venue exists but has no coordinates, pass its ID to the job
      existing_id = if existing, do: existing.id, else: nil

      # Schedule GoogleGeocodingJob to handle ONLY the geocoding lookup
      Logger.info("🔄 Scheduling geocoding lookup job for venue: #{attrs.name}")

      # Build job args from venue attributes
      job_args = %{
        "venue_name" => attrs.name,
        "address" => attrs.address,
        "phone" => attrs[:phone],
        "website" => attrs[:website],
        "facebook" => attrs[:facebook],
        "instagram" => attrs[:instagram],
        "existing_venue_id" => existing_id
      }

      # Queue the job and wait for it to complete
      case GoogleGeocodingJob.new(job_args)
           |> Oban.insert()
           |> wait_for_job() do
        {:ok, venue} ->
          Logger.info("✅ Geocoding job completed for venue: #{venue.name}")
          
          # Once we have the venue with coordinates, schedule places job
          # unless explicitly skipped
          venue = unless attrs[:skip_place_details] do
            schedule_place_details_job(venue)
          else
            venue
          end
          
          {:ok, venue}
        error -> error
      end
  end
end

# Helper to schedule a place details job
defp schedule_place_details_job(venue) do
  case GooglePlacesJob.new(%{"venue_id" => venue.id})
       |> Oban.insert() do
    {:ok, _job} ->
      Logger.info("🔄 Scheduled place details job for venue: #{venue.name}")
      venue
    {:error, reason} ->
      Logger.error("❌ Failed to schedule place details job: #{inspect(reason)}")
      venue
  end
end
```

#### 4. Modify GooglePlaceImageStore

Update GooglePlaceImageStore to use the new dedicated queue:

```elixir
def process_venue_images(%Venue{} = venue) do
  # Skip if no place_id
  if venue.place_id && venue.place_id != "" do
    Logger.info("🔄 Processing Google Place images for venue #{venue.id} (#{venue.name})")

    # Instead of direct API call, schedule through the places queue
    case GooglePlacesJob.new(%{
      "venue_id" => venue.id,
      "action" => "fetch_images"
    }) |> Oban.insert() do
      {:ok, _job} ->
        Logger.info("🔄 Scheduled image fetch job for venue: #{venue.name}")
        {:ok, venue}
      error ->
        error
    end
  else
    Logger.debug("⏭️ Skipping venue #{venue.id}: No place_id")
    {:ok, venue}
  end
end
```

## Benefits

This implementation provides several key benefits:

1. **Cost Tracking**
   - Separate queues make it easy to track costs for each API type
   - Can generate reports specifically for Place API usage

2. **Rate Limiting**
   - Can set different concurrency values for each queue
   - Place API can have more aggressive rate limiting than geocoding

3. **Debugging**
   - Clear separation of failures between geocoding and places
   - Easier to identify where issues occur

4. **Priority Control**
   - Can prioritize geocoding (required) over places (enhancement)
   - During high load, places jobs could be delayed more aggressively

## Monitoring and Analytics

Add enhanced monitoring with the new queues:

```elixir
# lib/trivia_advisor/application.ex
:telemetry.attach(
  "oban-google-places-job-success",
  [:oban, :job, :stop],
  fn [:oban, :job, :stop], %{duration: duration}, %{job: job}, _config ->
    if job.queue == "google_places" do
      # Record success metrics for google_places queue
      # Track costs, count, etc.
    end
  end,
  nil
)
```

## Migration Strategy

Rather than modify existing scrapers, implement this pattern with new scrapers first:

1. Configure the new queues
2. Create the new job modules
3. Use the new jobs in new scrapers
4. Gradually migrate existing scrapers as needed

This approach allows for incremental improvement without disrupting the existing functionality.

## Conclusion

By implementing dedicated Oban queues for Google API interactions, TriviaAdvisor can achieve better control over API usage, more accurate cost tracking, and improved system resilience. This architecture supports future growth with minimal disruption to the existing system. 
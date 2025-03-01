# TriviaAdvisor

TriviaAdvisor helps you find and track pub quiz nights and trivia events in your area. Think of it as a "Yelp for pub quizzes" - helping trivia enthusiasts discover new venues and keep track of their favorite quiz nights.

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
# 1. Initialize Scrape Log
source = Repo.get_by!(Source, website_url: @base_url)
{:ok, log} = ScrapeLog.create_log(source)

# 2. Fetch Venue List
# Question One: RSS feed pagination
# Inquizition: API endpoint
venues = fetch_venues()

# 3. Process Each Venue
detailed_venues = venues
|> Enum.map(&fetch_venue_details/1)
|> Enum.reject(&is_nil/1)

# 4. Update Scrape Log
ScrapeLog.update_log(log, %{
  success: true,
  total_venues: venue_count,
  metadata: %{
    venues: venues,
    started_at: start_time,
    completed_at: DateTime.utc_now()
  }
})
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
# 1. Top-level rescue
try do
  # Main scraping logic
rescue
  e ->
    ScrapeLog.log_error(log, e)
    Logger.error("Scraper failed: #{Exception.message(e)}")
    {:error, e}
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

### ⚠️ Important Notes
1. NEVER make DB migrations without asking first
2. Always follow the existing pattern for consistency
3. Maintain comprehensive logging
4. Handle errors gracefully
5. Use the VenueHelpers module for common functionality.
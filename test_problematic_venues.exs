import Ecto.Query
alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Locations.Venue
alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper

IO.puts("\n=== DETAILED VENUE PROCESSING TEST ===\n")

# Define the problematic venues - make sure to include all suspected venues
problematic_venues = [
  %{"name" => "The Bull", "address" => "100 Upper Street, Islington, N1 0NP"},
  %{"name" => "The Mitre", "address" => "291 Greenwich High Road, Greenwich, SE10 8NA"},
  %{"name" => "The White Horse", "address" => "1-3 Parsons Green, London SW6 4UL"},
  %{"name" => "The White Horse", "address" => "154-156 Fleet Rd, NW3 2QX"},
  %{"name" => "The Railway", "address" => "2 Greyhound Lane, Streatham Common, SW16 5SD"},
  %{"name" => "The Railway", "address" => "202 Upper Richmond Rd, London, SW15 6TD"}
]

# Get source for testing
source = Repo.get_by!(Source, name: "inquizition")
existing_sources_by_venue = InquizitionIndexJob.test_load_existing_sources(source.id)

IO.puts("Number of existing sources: #{map_size(existing_sources_by_venue)}")

# First pass - check which venues would be processed
IO.puts("\n=== CHECKING WHICH VENUES WOULD BE PROCESSED ===\n")
venues_that_would_be_processed = []

for venue_data <- problematic_venues do
  name = venue_data["name"]
  address = venue_data["address"]
  should_process = InquizitionIndexJob.test_should_process_venue?(venue_data, existing_sources_by_venue)

  # Extract postcode for direct validation
  postcode = case Regex.run(~r/[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}/i, address) do
    [matched_postcode] -> String.trim(matched_postcode)
    nil -> nil
  end

  # Check if venue exists with this postcode
  postcode_exists = if postcode do
    Repo.exists?(from v in Venue, where: v.postcode == ^postcode)
  else
    false
  end

  # Check if any venue exists with this name
  name_exists = Repo.exists?(from v in Venue, where: v.name == ^name)

  # Log detailed information for debugging
  IO.puts("#{name} - #{address}")
  IO.puts("  Postcode: #{postcode || "None"}")
  IO.puts("  Venue with this postcode exists? #{postcode_exists}")
  IO.puts("  Venue with this name exists? #{name_exists}")

  # Check if venue is in existing_sources_by_venue
  venue_key = InquizitionIndexJob.test_venue_key(name, address)
  has_source = Map.has_key?(existing_sources_by_venue, venue_key)
  IO.puts("  Has source in map? #{has_source}")
  if has_source do
    last_seen = Map.get(existing_sources_by_venue, venue_key)
    IO.puts("  Last seen: #{DateTime.to_iso8601(last_seen)}")
  end

  # Check database lookup function directly
  case InquizitionIndexJob.test_find_venue(name, address) do
    {:ok, venue} ->
      IO.puts("  ✅ Found venue in database: #{venue.name} (ID: #{venue.id}) with postcode #{venue.postcode}")
    {:error, _} ->
      IO.puts("  ❌ Did NOT find venue in database with lookup function")
  end

  IO.puts("  Would be processed? #{should_process}")

  if should_process do
    venues_that_would_be_processed = [venue_data | venues_that_would_be_processed]
  end

  IO.puts("")
end

# Now run the actual scraper process on these venues
IO.puts("\n=== TESTING ACTUAL SCRAPER PROCESSING LOGIC ===\n")

raw_venues = Scraper.fetch_raw_venues()
IO.puts("Total raw venues from scraper: #{length(raw_venues)}")

# Find the actual problematic venues that match our test data
matching_venues = Enum.filter(raw_venues, fn raw_venue ->
  Enum.any?(problematic_venues, fn test_venue ->
    raw_venue["name"] == test_venue["name"] &&
    String.contains?(raw_venue["address"] || "", test_venue["address"]) ||
    String.contains?(test_venue["address"], raw_venue["address"] || "")
  end)
end)

IO.puts("Found #{length(matching_venues)} matching problematic venues in raw data:")
Enum.each(matching_venues, fn v ->
  IO.puts("- #{v["name"]} at #{v["address"]}")
end)

# Manually run process_venues for these specific venues
IO.puts("\n=== MANUAL PROCESSING TEST ===\n")
{to_process, to_skip} = matching_venues
  |> Enum.split_with(fn venue_data ->
    InquizitionIndexJob.test_should_process_venue?(venue_data, existing_sources_by_venue)
  end)

IO.puts("Venues that WOULD BE processed (#{length(to_process)}):")
Enum.each(to_process, fn v -> IO.puts("- #{v["name"]} at #{v["address"]}") end)

IO.puts("\nVenues that WOULD BE skipped (#{length(to_skip)}):")
Enum.each(to_skip, fn v -> IO.puts("- #{v["name"]} at #{v["address"]}") end)

# Run the full job for verification
IO.puts("\n=== RUNNING FULL JOB (limited to problematic venues) ===\n")
Enum.each(matching_venues, fn venue ->
  IO.puts("Checking venue: #{venue["name"]} at #{venue["address"]}")
  should_process = InquizitionIndexJob.test_should_process_venue?(venue, existing_sources_by_venue)
  IO.puts("   Should process: #{should_process}")
end)

# Add a function to test the venue key generation
defmodule TestHelpers do
  def extract_actual_venues_being_processed(venues) do
    source = Repo.get_by!(Source, name: "inquizition")
    existing_sources = InquizitionIndexJob.test_load_existing_sources(source.id)

    Enum.filter(venues, fn venue ->
      InquizitionIndexJob.test_should_process_venue?(venue, existing_sources)
    end)
  end
end

# Get actual venues being processed from the full dataset
if length(raw_venues) > 0 do
  processed_venues = TestHelpers.extract_actual_venues_being_processed(raw_venues)
  IO.puts("\n=== ALL VENUES THAT WOULD BE PROCESSED (#{length(processed_venues)}/#{length(raw_venues)}) ===\n")

  Enum.each(processed_venues, fn venue ->
    IO.puts("- #{venue["name"]} at #{venue["address"] || "[No address]"}")
  end)
end

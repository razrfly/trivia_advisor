require Logger
alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Debug.Helpers

Logger.info("🧪 Starting postcode lookup test...")

test_venues = [
  %{"name" => "The White Horse", "address" => "154-156 Fleet Rd, NW3 2QX"},
  %{"name" => "The White Horse", "address" => "20-22, Peckham Rye, Peckham Rye, SE15 4JR"}
]

for venue <- test_venues do
  Logger.info("🔍 Testing venue: #{venue["name"]} at #{venue["address"]}")

  # Normalize the venue data
  venue_name = venue["name"]
  venue_address = venue["address"]

  # Try to find the venue
  case Helpers.find_inquizition_venue(venue_name, venue_address) do
    {:ok, found_venue} ->
      Logger.info("✅ Found venue: #{found_venue.name} at #{found_venue.address} with postcode #{found_venue.postcode}")
    {:error, _} ->
      Logger.error("❌ No venue found")
  end
end

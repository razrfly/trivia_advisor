# Script to test which countries and cities have venues
# Run with: mix run lib/debug/test_image_refresher.exs

alias TriviaAdvisor.Locations.Country
alias TriviaAdvisor.Locations.City
alias TriviaAdvisor.Repo
import Ecto.Query

# Get countries with venues
countries_query = from c in Country,
  join: city in assoc(c, :cities),
  join: v in assoc(city, :venues),
  distinct: true,
  select: c.name

countries_with_venues = Repo.all(countries_query)

# Get all countries
all_countries = Repo.all(from c in Country, select: c.name)

# Get cities with venues
cities_query = from c in City,
  join: v in assoc(c, :venues),
  distinct: true,
  select: c.name

cities_with_venues = Repo.all(cities_query)

# Get all cities
all_cities = Repo.all(from c in City, select: c.name)

IO.puts("Countries with venues (#{length(countries_with_venues)}/#{length(all_countries)}):")
Enum.each(countries_with_venues, fn country -> IO.puts("- #{country}") end)

IO.puts("\nCities with venues (#{length(cities_with_venues)}/#{length(all_cities)}):")
Enum.each(cities_with_venues |> Enum.sort(), fn city -> IO.puts("- #{city}") end)

IO.puts("\nCountries without venues (#{length(all_countries) - length(countries_with_venues)}):")
countries_without_venues = all_countries -- countries_with_venues
Enum.each(countries_without_venues |> Enum.sort(), fn country -> IO.puts("- #{country}") end)

# Count venues per country
country_venue_counts = from c in Country,
  join: city in assoc(c, :cities),
  join: v in assoc(city, :venues),
  group_by: c.name,
  select: {c.name, count(v.id)},
  order_by: [desc: count(v.id)]

IO.puts("\nVenue counts per country:")
Repo.all(country_venue_counts)
|> Enum.each(fn {country, count} -> IO.puts("- #{country}: #{count} venues") end)

# Script to fix empty gallery entries in the database
# Run with: mix run fix_empty_galleries.exs

alias TriviaAdvisor.Repo
alias TriviaAdvisor.Locations.{City, Country}
require Logger
import Ecto.Query

Logger.info("Starting to fix empty image galleries...")

# Fix country galleries
from(c in Country,
  where: fragment("?->>'images' = '[]'", c.unsplash_gallery) and
         fragment("?->>'last_refreshed_at' is not null", c.unsplash_gallery))
|> Repo.all()
|> Enum.each(fn country ->
  Logger.info("Fixing empty gallery for country: #{country.name}")

  gallery = country.unsplash_gallery
  |> Map.drop(["last_refreshed_at"])

  {:ok, _} = Repo.update(Country.changeset(country, %{unsplash_gallery: gallery}))
end)

# Fix city galleries
from(c in City,
  where: fragment("?->>'images' = '[]'", c.unsplash_gallery) and
         fragment("?->>'last_refreshed_at' is not null", c.unsplash_gallery))
|> Repo.all()
|> Enum.each(fn city ->
  Logger.info("Fixing empty gallery for city: #{city.name}")

  gallery = city.unsplash_gallery
  |> Map.drop(["last_refreshed_at"])

  {:ok, _} = Repo.update(City.changeset(city, %{unsplash_gallery: gallery}))
end)

# Count remaining empty galleries
country_count =
  from(c in Country,
    where: fragment("?->>'images' = '[]'", c.unsplash_gallery))
  |> Repo.aggregate(:count)

city_count =
  from(c in City,
    where: fragment("?->>'images' = '[]'", c.unsplash_gallery))
  |> Repo.aggregate(:count)

Logger.info("Fix complete!")
Logger.info("Remaining empty galleries: #{country_count} countries, #{city_count} cities")
Logger.info("These empty galleries will be refreshed on the next scheduled run.")

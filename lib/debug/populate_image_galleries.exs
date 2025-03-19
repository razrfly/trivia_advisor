defmodule TriviaAdvisor.Debug.PopulateImageGalleries do
  @moduledoc """
  Script to populate image galleries for countries and cities.

  Run with: mix run lib/debug/populate_image_galleries.exs
  """

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{Country, City}
  alias TriviaAdvisor.Services.UnsplashImageFetcher

  def run() do
    Logger.info("Starting to populate image galleries...")

    # Process top 5 countries with the most venues
    populate_top_countries(5)

    # Process 5 random cities from each of those countries
    countries = get_top_countries(5)

    Enum.each(countries, fn country ->
      cities = get_random_cities_for_country(country.id, 5)
      Logger.info("Processing #{length(cities)} cities for #{country.name}")

      Enum.each(cities, fn city ->
        Logger.info("Fetching and storing images for city: #{city.name}")
        UnsplashImageFetcher.fetch_and_store_city_images(city.name, country.name)
        Process.sleep(2000) # Avoid rate limiting
      end)
    end)

    Logger.info("Image galleries populated successfully!")
  end

  def populate_top_countries(count) do
    countries = get_top_countries(count)

    Logger.info("Processing #{length(countries)} countries with the most venues")

    Enum.each(countries, fn country ->
      Logger.info("Fetching and storing images for country: #{country.name}")
      UnsplashImageFetcher.fetch_and_store_country_images(country.name)
      Process.sleep(2000) # Avoid rate limiting
    end)
  end

  def get_top_countries(count) do
    # Get countries with the most venues
    country_query = from c in Country,
      join: city in assoc(c, :cities),
      join: venue in assoc(city, :venues),
      group_by: c.id,
      order_by: [desc: count(venue.id)],
      select: %{id: c.id, name: c.name, venues_count: count(venue.id)},
      limit: ^count

    country_ids = Repo.all(country_query) |> Enum.map(& &1.id)

    # Fetch full country records
    from(c in Country, where: c.id in ^country_ids)
    |> Repo.all()
  end

  def get_random_cities_for_country(country_id, count) do
    from(c in City,
      where: c.country_id == ^country_id,
      join: v in assoc(c, :venues),
      distinct: true,
      order_by: fragment("RANDOM()"),
      limit: ^count)
    |> Repo.all()
  end
end

# Run the script
TriviaAdvisor.Debug.PopulateImageGalleries.run()

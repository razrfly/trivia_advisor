defmodule TriviaAdvisor.Scraping.Scrapers.Pubquiz.Scraper do
  @moduledoc """
  Scraper for pubquiz.pl
  """

  require Logger
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor

  @base_url "https://pubquiz.pl/bilety/"

  def fetch_venues do
    with {:ok, cities} <- fetch_cities(),
         venues <- fetch_venues_from_cities(cities),
         venues <- List.flatten(venues),
         venues_with_details <- fetch_venue_details(venues) do
      {:ok, venues_with_details}
    end
  end

  defp fetch_cities do
    case HTTPoison.get(@base_url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        cities = Extractor.extract_cities(body)
        {:ok, cities}

      {:ok, %{status_code: status}} ->
        Logger.error("Failed to fetch cities. Status: #{status}")
        {:error, :http_error}

      {:error, error} ->
        Logger.error("Failed to fetch cities: #{inspect(error)}")
        {:error, error}
    end
  end

  defp fetch_venues_from_cities(cities) do
    cities
    |> Enum.map(fn city_url ->
      case HTTPoison.get(city_url, [], follow_redirect: true) do
        {:ok, %{status_code: 200, body: body}} ->
          Extractor.extract_venues(body)

        {:ok, %{status_code: status}} ->
          Logger.error("Failed to fetch venues for #{city_url}. Status: #{status}")
          []

        {:error, error} ->
          Logger.error("Failed to fetch venues for #{city_url}: #{inspect(error)}")
          []
      end
    end)
  end

  defp fetch_venue_details(venues) do
    venues
    |> Enum.map(fn venue ->
      case HTTPoison.get(venue.url, [], follow_redirect: true) do
        {:ok, %{status_code: 200, body: body}} ->
          details = Extractor.extract_venue_details(body)
          Map.merge(venue, details)

        {:ok, %{status_code: status}} ->
          Logger.error("Failed to fetch details for #{venue.name}. Status: #{status}")
          venue

        {:error, error} ->
          Logger.error("Failed to fetch details for #{venue.name}: #{inspect(error)}")
          venue
      end
    end)
  end
end

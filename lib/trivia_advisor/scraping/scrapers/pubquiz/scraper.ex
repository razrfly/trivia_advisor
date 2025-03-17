defmodule TriviaAdvisor.Scraping.Scrapers.Pubquiz.Scraper do
  @moduledoc """
  Scraper for pubquiz.pl
  """

  require Logger
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor

  @base_url "https://pubquiz.pl/bilety/"

  def fetch_venues do
    with {:ok, cities} <- fetch_cities(),
         venues <- fetch_venues_from_cities(cities) do
      {:ok, List.flatten(venues)}
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
end

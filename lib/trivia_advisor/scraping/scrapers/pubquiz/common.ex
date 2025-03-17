defmodule TriviaAdvisor.Scraping.Scrapers.Pubquiz.Common do
  @moduledoc """
  Common functions for the Pubquiz scraper.
  Shared between the legacy scraper and the Oban job implementations.
  """

  require Logger
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor

  @base_url "https://pubquiz.pl/bilety/"

  @doc """
  Returns the base URL for the pubquiz.pl website.
  """
  def base_url, do: @base_url

  @doc """
  Fetches the list of cities from pubquiz.pl
  """
  def fetch_cities do
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

  @doc """
  Fetches venues from a list of city URLs
  """
  def fetch_venues_from_cities(cities) do
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

  @doc """
  Fetches detailed information for each venue
  """
  def fetch_venue_details(venues) do
    venues
    |> Enum.map(fn venue ->
      case HTTPoison.get(venue["url"], [], follow_redirect: true) do
        {:ok, %{status_code: 200, body: body}} ->
          details = Extractor.extract_venue_details(body)
          Map.merge(venue, details)

        {:ok, %{status_code: status}} ->
          Logger.error("Failed to fetch details for #{venue["name"]}. Status: #{status}")
          venue

        {:error, error} ->
          Logger.error("Failed to fetch details for #{venue["name"]}: #{inspect(error)}")
          venue
      end
    end)
  end
end

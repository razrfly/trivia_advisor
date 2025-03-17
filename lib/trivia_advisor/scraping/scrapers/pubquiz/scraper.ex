defmodule TriviaAdvisor.Scraping.Scrapers.Pubquiz.Scraper do
  @moduledoc """
  Scraper for pubquiz.pl

  Note: This is the legacy implementation. New code should use the Oban job implementation.
  This module now delegates to the Common module for all functionality.
  """

  require Logger
  alias TriviaAdvisor.Scraping.Scrapers.Pubquiz.Common

  def fetch_venues do
    with {:ok, cities} <- Common.fetch_cities(),
         venues <- Common.fetch_venues_from_cities(cities),
         venues <- List.flatten(venues),
         venues_with_details <- Common.fetch_venue_details(venues) do
      {:ok, venues_with_details}
    end
  end
end

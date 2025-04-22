defmodule TriviaAdvisor.VenueStatistics do
  @moduledoc """
  Context module for handling venue statistics and geographical data for visualizations.
  """

  import Ecto.Query, warn: false
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{Venue, City, Country}
  alias TriviaAdvisor.Cache

  # Cache key for active venues count
  @active_venues_count_key "venue_statistics:active_venues_count"
  # Cache key for venues by country data
  @venues_by_country_key "venue_statistics:venues_by_country"
  # TTL for cache in seconds (24 hours)
  @cache_ttl 86_400

  @doc """
  Count the number of active venues that have been seen in the last 30 days.
  Results are cached for 24 hours for performance.

  ## Options
    * `:force_refresh` - whether to force a cache refresh (default: false)

  ## Examples

      iex> count_active_venues()
      1042

  """
  def count_active_venues(opts \\ []) do
    force_refresh = Keyword.get(opts, :force_refresh, false)

    if force_refresh do
      fetch_and_cache_active_venues_count()
    else
      case Cache.get(@active_venues_count_key) do
        nil ->
          fetch_and_cache_active_venues_count()
        cached_count ->
          cached_count
      end
    end
  end

  @doc """
  Get the count of countries that have venues.

  ## Examples

      iex> count_countries_with_venues()
      9

  """
  def count_countries_with_venues do
    venues_by_country()
    |> Enum.count()
  end

  @doc """
  Get venues grouped by country for map visualization.
  Returns a list of maps with country code, name, and venue count.
  Results are cached for 24 hours for performance.

  ## Options
    * `:force_refresh` - whether to force a cache refresh (default: false)

  ## Examples

      iex> venues_by_country()
      [
        %{country_code: "GB", country_name: "United Kingdom", venue_count: 532},
        %{country_code: "US", country_name: "United States", venue_count: 245},
        # ...
      ]

  """
  def venues_by_country(opts \\ []) do
    force_refresh = Keyword.get(opts, :force_refresh, false)

    if force_refresh do
      fetch_and_cache_venues_by_country()
    else
      case Cache.get(@venues_by_country_key) do
        nil ->
          fetch_and_cache_venues_by_country()
        cached_data ->
          cached_data
      end
    end
  end

  # Private function to fetch active venues count
  defp fetch_and_cache_active_venues_count do
    # For this prototype, we're counting all venues
    # In production, we would add a filter for "last_seen_at" within 30 days
    query = from v in Venue,
            select: count(v.id)

    count = Repo.one(query) || 0

    # Cache the result
    Cache.put(@active_venues_count_key, count, ttl: @cache_ttl)

    count
  end

  # Private function to fetch venues by country
  defp fetch_and_cache_venues_by_country do
    # Query venues grouped by country with counts
    query = from v in Venue,
            join: city in assoc(v, :city),
            join: country in assoc(city, :country),
            group_by: [country.id, country.name, country.code],
            select: %{
              country_id: country.id,
              country_code: country.code,
              country_name: country.name,
              venue_count: count(v.id)
            },
            order_by: [desc: count(v.id)]

    venues_by_country = Repo.all(query)

    # Cache the result
    Cache.put(@venues_by_country_key, venues_by_country, ttl: @cache_ttl)

    venues_by_country
  end

  @doc """
  Schedule a background job to refresh venue statistics.
  This will update the cached data asynchronously.

  Returns :ok on success.
  """
  def schedule_refresh do
    # For the prototype, we'll just directly refresh the cache
    # In production, we'd use Oban to schedule a background job
    fetch_and_cache_active_venues_count()
    fetch_and_cache_venues_by_country()
    :ok
  end
end

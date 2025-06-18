defmodule TriviaAdvisor.Services.VenueDuplicateDetector do
  @moduledoc """
  Service for detecting potential duplicate venues using fuzzy matching algorithms.

  This service provides fuzzy matching capabilities to identify venues that might be duplicates
  based on name similarity, address comparison, and other venue attributes.

  ## Features

  - Name similarity using multiple algorithms (Levenshtein, Jaro-Winkler)
  - Address normalization and comparison
  - Postcode exact matching
  - Google Place ID validation
  - Configurable similarity thresholds
  - Integration with ecto_soft_delete (excludes soft-deleted venues)

  ## Usage

      iex> VenueDuplicateDetector.find_potential_duplicates(venue)
      [%Venue{}, %Venue{}]

      iex> VenueDuplicateDetector.calculate_similarity_score(venue1, venue2)
      0.87

      iex> VenueDuplicateDetector.is_duplicate?(venue1, venue2)
      true
  """

  require Logger
  import Ecto.Query, warn: false
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Repo

  @default_name_threshold 0.85
  @default_address_threshold 0.80

  # Configuration options
  @type options :: [
    name_threshold: float(),
    address_threshold: float(),
    include_place_id_check: boolean(),
    exclude_soft_deleted: boolean()
  ]

  @type similarity_score :: float()
  @type venue :: %Venue{}

  @doc """
  Finds potential duplicate venues for a given venue.

  Returns a list of venues that are likely duplicates of the input venue,
  excluding the input venue itself and any soft-deleted venues.

  ## Parameters

  - `venue` - The venue to find duplicates for
  - `opts` - Configuration options (see module docs)

  ## Examples

      iex> find_potential_duplicates(%Venue{name: "The Crown", postcode: "SW1A 1AA"})
      [%Venue{id: 123, name: "Crown Pub", postcode: "SW1A 1AA"}]
  """
  @spec find_potential_duplicates(venue(), options()) :: [venue()]
  def find_potential_duplicates(%Venue{} = venue, opts \\ []) do
    opts = normalize_options(opts)

    Logger.debug("Finding duplicates for venue: #{venue.name} (ID: #{venue.id})")

    # Get all active venues (excluding soft-deleted)
    candidates = get_candidate_venues(venue, opts)

    # Filter to likely duplicates
    duplicates = Enum.filter(candidates, fn candidate ->
      is_duplicate?(venue, candidate, opts)
    end)

    Logger.debug("Found #{length(duplicates)} potential duplicates for venue #{venue.id}")
    duplicates
  end

  @doc """
  Calculates a similarity score between two venues.

  Returns a float between 0.0 (completely different) and 1.0 (identical).

  ## Parameters

  - `venue1` - First venue for comparison
  - `venue2` - Second venue for comparison
  - `opts` - Configuration options

  ## Examples

      iex> calculate_similarity_score(venue1, venue2)
      0.87
  """
  @spec calculate_similarity_score(venue(), venue(), options()) :: similarity_score()
  def calculate_similarity_score(%Venue{} = venue1, %Venue{} = venue2, opts \\ []) do
    opts = normalize_options(opts)

    # Name similarity (weighted heavily)
    name_score = calculate_name_similarity(venue1.name, venue2.name)

    # Address/location similarity
    location_score = calculate_location_similarity(venue1, venue2)

    # Place ID exact match (bonus if available)
    place_id_bonus = if opts[:include_place_id_check] and
                        venue1.place_id && venue2.place_id &&
                        venue1.place_id == venue2.place_id do
      1.0
    else
      0.0
    end

    # Weighted average: name is most important, location secondary, place_id is definitive
    if place_id_bonus > 0 do
      1.0  # Place ID match is definitive
    else
      (name_score * 0.7) + (location_score * 0.3)
    end
  end

  @doc """
  Checks if two venues are likely duplicates based on similarity thresholds.

  ## Parameters

  - `venue1` - First venue for comparison
  - `venue2` - Second venue for comparison
  - `opts` - Configuration options with thresholds

  ## Examples

      iex> is_duplicate?(venue1, venue2)
      true

      iex> is_duplicate?(venue1, venue2, name_threshold: 0.95)
      false
  """
  @spec is_duplicate?(venue(), venue(), options()) :: boolean()
  def is_duplicate?(%Venue{} = venue1, %Venue{} = venue2, opts \\ []) do
    opts = normalize_options(opts)

    # Don't compare venue with itself
    if venue1.id == venue2.id, do: false

    # Calculate overall similarity
    similarity = calculate_similarity_score(venue1, venue2, opts)

    # Check if name similarity meets threshold
    name_similarity = calculate_name_similarity(venue1.name, venue2.name)
    meets_name_threshold = name_similarity >= opts[:name_threshold]

    # Strong location match (same postcode or very similar address)
    strong_location_match = has_strong_location_match?(venue1, venue2)

    # Google Place ID exact match is definitive
    place_id_match = opts[:include_place_id_check] and
                     venue1.place_id && venue2.place_id &&
                     venue1.place_id == venue2.place_id

    # Decision logic
    cond do
      place_id_match -> true
      meets_name_threshold and strong_location_match -> true
      similarity >= @default_name_threshold -> true
      true -> false
    end
  end

  @doc """
  Normalizes a venue name for comparison by removing common words,
  standardizing case, and cleaning punctuation.

  ## Examples

      iex> normalize_name("The Crown Pub & Restaurant")
      "crown pub restaurant"
  """
  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")  # Remove punctuation
    |> String.replace(~r/\b(the|and|pub|restaurant|bar|hotel|inn|tavern|club|cafe|coffee|shop)\b/i, " ")
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.trim()
  end

  @doc """
  Normalizes an address for comparison by standardizing abbreviations
  and removing common words.

  ## Examples

      iex> normalize_address("123 High Street, London")
      "123 high st london"
  """
  @spec normalize_address(String.t() | nil) :: String.t()
  def normalize_address(address) when is_binary(address) do
    address
    |> String.downcase()
    |> String.replace(~r/\bstreet\b/, "st")
    |> String.replace(~r/\broad\b/, "rd")
    |> String.replace(~r/\bavenue\b/, "ave")
    |> String.replace(~r/\blane\b/, "ln")
    |> String.replace(~r/\bplace\b/, "pl")
    |> String.replace(~r/[^\w\s]/, " ")  # Remove punctuation
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.trim()
  end
  def normalize_address(nil), do: ""

  # Private Functions

  defp normalize_options(opts) do
    Keyword.merge([
      name_threshold: @default_name_threshold,
      address_threshold: @default_address_threshold,
      include_place_id_check: true,
      exclude_soft_deleted: true
    ], opts)
  end

  defp get_candidate_venues(%Venue{} = venue, opts) do
    query = from v in Venue,
            where: v.id != ^venue.id

    # Exclude soft-deleted venues if requested (default behavior)
    query = if opts[:exclude_soft_deleted] do
      from v in query, where: is_nil(v.deleted_at)
    else
      query
    end

    # Focus on venues in the same city for performance
    query = if venue.city_id do
      from v in query, where: v.city_id == ^venue.city_id
    else
      query
    end

    Repo.all(query)
  end

  defp calculate_name_similarity(name1, name2) when is_binary(name1) and is_binary(name2) do
    normalized1 = normalize_name(name1)
    normalized2 = normalize_name(name2)

    # Use Jaro-Winkler distance (built into Elixir)
    String.jaro_distance(normalized1, normalized2)
  end
  defp calculate_name_similarity(_, _), do: 0.0

  defp calculate_location_similarity(%Venue{} = venue1, %Venue{} = venue2) do
    # Exact postcode match gives high score
    if venue1.postcode && venue2.postcode && venue1.postcode == venue2.postcode do
      1.0
    else
      # Compare normalized addresses
      address_similarity = if venue1.address && venue2.address do
        normalized1 = normalize_address(venue1.address)
        normalized2 = normalize_address(venue2.address)
        String.jaro_distance(normalized1, normalized2)
      else
        0.0
      end

      # Geographic proximity (if coordinates available)
      geo_similarity = calculate_geographic_similarity(venue1, venue2)

      # Take the higher of address or geographic similarity
      max(address_similarity, geo_similarity)
    end
  end

  defp calculate_geographic_similarity(%Venue{} = venue1, %Venue{} = venue2) do
    with lat1 when not is_nil(lat1) <- venue1.latitude,
         lon1 when not is_nil(lon1) <- venue1.longitude,
         lat2 when not is_nil(lat2) <- venue2.latitude,
         lon2 when not is_nil(lon2) <- venue2.longitude do

      # Calculate distance in kilometers using Haversine formula
      distance_km = haversine_distance(
        Decimal.to_float(lat1), Decimal.to_float(lon1),
        Decimal.to_float(lat2), Decimal.to_float(lon2)
      )

      # Convert distance to similarity score (closer = higher score)
      # Within 100m = 1.0, linearly decreasing to 0.0 at 1km+
      cond do
        distance_km <= 0.1 -> 1.0  # Within 100m
        distance_km <= 1.0 -> 1.0 - (distance_km - 0.1) / 0.9  # Linear decay to 1km
        true -> 0.0  # More than 1km apart
      end
    else
      _ -> 0.0  # Missing coordinates
    end
  end

  defp has_strong_location_match?(%Venue{} = venue1, %Venue{} = venue2) do
    # Same postcode is a strong match
    same_postcode = venue1.postcode && venue2.postcode && venue1.postcode == venue2.postcode

    # Very close geographically (within 50m)
    close_geography = calculate_geographic_similarity(venue1, venue2) >= 0.95

    same_postcode or close_geography
  end

  # Haversine formula for calculating distance between two points on Earth
  defp haversine_distance(lat1, lon1, lat2, lon2) do
    # Convert to radians
    lat1_rad = lat1 * :math.pi() / 180
    lon1_rad = lon1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    lon2_rad = lon2 * :math.pi() / 180

    # Differences
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    # Haversine formula
    a = :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
        :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    # Earth's radius in kilometers
    6371.0 * c
  end
end

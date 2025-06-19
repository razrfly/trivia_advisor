defmodule TriviaAdvisor.Services.FuzzyDuplicateProcessor do
  @moduledoc """
  Service for processing venues to find fuzzy duplicates using VenueDuplicateDetector
  and storing them in the venue_fuzzy_duplicates table with confidence scores.

  This service bridges the gap between the sophisticated VenueDuplicateDetector
  and the admin interface by batch processing all venues and storing results
  in a queryable format with confidence scoring.
  """

  require Logger
  import Ecto.Query, warn: false

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Locations.VenueFuzzyDuplicate
  alias TriviaAdvisor.Services.VenueDuplicateDetector

  @doc """
  Processes all venues to find fuzzy duplicates and stores them in the database.

  ## Options

  - `:batch_size` - Number of venues to process in each batch (default: 100)
  - `:min_confidence` - Minimum confidence score to store (default: 0.70)
  - `:clear_existing` - Whether to clear existing records first (default: false)
  - `:progress_callback` - Function to call with progress updates

  ## Examples

      iex> FuzzyDuplicateProcessor.process_all_venues()
      {:ok, %{processed: 1500, duplicates_found: 245, duplicates_stored: 180}}

      iex> FuzzyDuplicateProcessor.process_all_venues(min_confidence: 0.80)
      {:ok, %{processed: 1500, duplicates_found: 156, duplicates_stored: 156}}
  """
  def process_all_venues(opts \\ []) do
    opts = normalize_options(opts)

    Logger.info("Starting fuzzy duplicate processing with options: #{inspect(opts)}")

    if opts[:clear_existing] do
      Logger.info("Clearing existing fuzzy duplicates...")
      Repo.delete_all(VenueFuzzyDuplicate)
    end

    # Get all active venues
    venues = get_active_venues()
    total_venues = length(venues)

    Logger.info("Processing #{total_venues} venues for fuzzy duplicates...")

    # Process venues in batches
    results = venues
    |> Enum.chunk_every(opts[:batch_size])
    |> Enum.with_index()
    |> Enum.reduce(%{processed: 0, duplicates_found: 0, duplicates_stored: 0}, fn {batch, batch_index}, acc ->
      batch_start = batch_index * opts[:batch_size] + 1
      batch_end = min(batch_start + length(batch) - 1, total_venues)

      Logger.info("Processing batch #{batch_index + 1}: venues #{batch_start}-#{batch_end}")

      batch_results = process_venue_batch(batch, opts)

      new_acc = %{
        processed: acc.processed + batch_results.processed,
        duplicates_found: acc.duplicates_found + batch_results.duplicates_found,
        duplicates_stored: acc.duplicates_stored + batch_results.duplicates_stored
      }

      # Call progress callback if provided
      if opts[:progress_callback] do
        progress = %{
          batch: batch_index + 1,
          total_batches: ceil(total_venues / opts[:batch_size]),
          venues_processed: new_acc.processed,
          total_venues: total_venues,
          duplicates_found: new_acc.duplicates_found,
          duplicates_stored: new_acc.duplicates_stored
        }
        opts[:progress_callback].(progress)
      end

      new_acc
    end)

    Logger.info("Fuzzy duplicate processing complete: #{inspect(results)}")
    {:ok, results}
  end

  @doc """
  Processes a single venue to find its duplicates and store them.

  Useful for incremental processing when new venues are added.
  """
  def process_venue(%Venue{} = venue, opts \\ []) do
    opts = normalize_options(opts)

    Logger.debug("Processing venue #{venue.id} (#{venue.name}) for duplicates")

    # Find potential duplicates using the detector
    potential_duplicates = VenueDuplicateDetector.find_potential_duplicates(venue,
      name_threshold: opts[:min_confidence] * 0.9  # Slightly lower threshold for detection
    )

    stored_count = potential_duplicates
    |> Enum.map(fn duplicate_venue ->
      create_fuzzy_duplicate_record(venue, duplicate_venue, opts)
    end)
    |> Enum.count(fn result -> match?({:ok, _}, result) end)

    %{
      processed: 1,
      duplicates_found: length(potential_duplicates),
      duplicates_stored: stored_count
    }
  end

  @doc """
  Gets statistics about the current fuzzy duplicates.
  """
  def get_statistics do
    query = from fd in VenueFuzzyDuplicate,
            select: %{
              total: count(fd.id),
              high_confidence: filter(count(fd.id), fd.confidence_score >= 0.90),
              medium_confidence: filter(count(fd.id), fd.confidence_score >= 0.75 and fd.confidence_score < 0.90),
              low_confidence: filter(count(fd.id), fd.confidence_score < 0.75),
              pending: filter(count(fd.id), fd.status == "pending"),
              reviewed: filter(count(fd.id), fd.status == "reviewed"),
              merged: filter(count(fd.id), fd.status == "merged"),
              rejected: filter(count(fd.id), fd.status == "rejected"),
              avg_confidence: avg(fd.confidence_score),
              avg_name_similarity: avg(fd.name_similarity),
              avg_location_similarity: avg(fd.location_similarity)
            }

    Repo.one(query) || %{}
  end

  @doc """
  Updates the status of existing fuzzy duplicate records based on merge logs.

  This synchronizes the fuzzy duplicates table with actions taken through
  the VenueMergeService.
  """
  def sync_with_merge_logs do
    # Mark merged pairs
    merged_query = """
    UPDATE venue_fuzzy_duplicates
    SET status = 'merged', reviewed_at = vml.inserted_at, reviewed_by = vml.performed_by
    FROM venue_merge_logs vml
    WHERE vml.action_type = 'merge'
    AND ((venue_fuzzy_duplicates.venue1_id = vml.primary_venue_id AND venue_fuzzy_duplicates.venue2_id = vml.secondary_venue_id)
         OR (venue_fuzzy_duplicates.venue1_id = vml.secondary_venue_id AND venue_fuzzy_duplicates.venue2_id = vml.primary_venue_id))
    AND venue_fuzzy_duplicates.status = 'pending'
    """

    # Mark rejected pairs
    rejected_query = """
    UPDATE venue_fuzzy_duplicates
    SET status = 'rejected', reviewed_at = vml.inserted_at, reviewed_by = vml.performed_by
    FROM venue_merge_logs vml
    WHERE vml.action_type = 'not_duplicate'
    AND ((venue_fuzzy_duplicates.venue1_id = vml.primary_venue_id AND venue_fuzzy_duplicates.venue2_id = vml.secondary_venue_id)
         OR (venue_fuzzy_duplicates.venue1_id = vml.secondary_venue_id AND venue_fuzzy_duplicates.venue2_id = vml.primary_venue_id))
    AND venue_fuzzy_duplicates.status = 'pending'
    """

    merged_result = Repo.query!(merged_query)
    rejected_result = Repo.query!(rejected_query)

    Logger.info("Synced fuzzy duplicates with merge logs: #{merged_result.num_rows} merged, #{rejected_result.num_rows} rejected")

    {:ok, %{merged: merged_result.num_rows, rejected: rejected_result.num_rows}}
  end

  # Private functions

  defp normalize_options(opts) do
    Keyword.merge([
      batch_size: 100,
      min_confidence: 0.70,
      clear_existing: false,
      progress_callback: nil
    ], opts)
  end

  defp get_active_venues do
    from(v in Venue,
         where: is_nil(v.deleted_at),
         order_by: v.id)
    |> Repo.all()
  end

  defp process_venue_batch(venues, opts) do
    venues
    |> Enum.reduce(%{processed: 0, duplicates_found: 0, duplicates_stored: 0}, fn venue, acc ->
      venue_results = process_venue(venue, opts)
      %{
        processed: acc.processed + venue_results.processed,
        duplicates_found: acc.duplicates_found + venue_results.duplicates_found,
        duplicates_stored: acc.duplicates_stored + venue_results.duplicates_stored
      }
    end)
  end

  defp create_fuzzy_duplicate_record(%Venue{} = venue1, %Venue{} = venue2, opts) do
    # Calculate detailed similarity metrics
    confidence_score = VenueDuplicateDetector.calculate_similarity_score(venue1, venue2)

    # Skip if below minimum confidence
    if confidence_score < opts[:min_confidence] do
      {:skipped, :below_threshold}
    else
      name_similarity = calculate_name_similarity(venue1.name, venue2.name)
      location_similarity = calculate_location_similarity(venue1, venue2)
      match_criteria = determine_match_criteria(venue1, venue2)

      attrs = %{
        venue1_id: venue1.id,
        venue2_id: venue2.id,
        confidence_score: confidence_score,
        name_similarity: name_similarity,
        location_similarity: location_similarity,
        match_criteria: match_criteria
      }

      %VenueFuzzyDuplicate{}
      |> VenueFuzzyDuplicate.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing)  # Ignore if already exists
    end
  end

  defp calculate_name_similarity(name1, name2) when is_binary(name1) and is_binary(name2) do
    normalized1 = VenueDuplicateDetector.normalize_name(name1)
    normalized2 = VenueDuplicateDetector.normalize_name(name2)
    String.jaro_distance(normalized1, normalized2)
  end
  defp calculate_name_similarity(_, _), do: 0.0

  defp calculate_location_similarity(%Venue{} = venue1, %Venue{} = venue2) do
    cond do
      # Exact postcode match
      venue1.postcode && venue2.postcode && venue1.postcode == venue2.postcode -> 1.0

      # Address similarity
      venue1.address && venue2.address ->
        norm1 = VenueDuplicateDetector.normalize_address(venue1.address)
        norm2 = VenueDuplicateDetector.normalize_address(venue2.address)
        String.jaro_distance(norm1, norm2)

      # Geographic proximity (if coordinates available)
      venue1.latitude && venue1.longitude && venue2.latitude && venue2.longitude ->
        calculate_geographic_similarity(venue1, venue2)

      true -> 0.0
    end
  end

  defp calculate_geographic_similarity(%Venue{} = venue1, %Venue{} = venue2) do
    # This duplicates some logic from VenueDuplicateDetector but keeps it self-contained
    with lat1 when not is_nil(lat1) <- venue1.latitude,
         lon1 when not is_nil(lon1) <- venue1.longitude,
         lat2 when not is_nil(lat2) <- venue2.latitude,
         lon2 when not is_nil(lon2) <- venue2.longitude do

      # Simple distance calculation (could use the full haversine from VenueDuplicateDetector)
      lat_diff = abs(to_float(lat1) - to_float(lat2))
      lon_diff = abs(to_float(lon1) - to_float(lon2))

      # Very rough approximation: within ~0.001 degrees (about 100m) = high similarity
      total_diff = lat_diff + lon_diff
      case total_diff do
        d when d <= 0.001 -> 1.0
        d when d <= 0.01 -> 1.0 - (d - 0.001) / 0.009
        _ -> 0.0
      end
    else
      _ -> 0.0
    end
  end

  defp determine_match_criteria(%Venue{} = venue1, %Venue{} = venue2) do
    criteria = []

    # Name similarity
    name_sim = calculate_name_similarity(venue1.name, venue2.name)
    criteria = if name_sim >= 0.85, do: ["similar_name" | criteria], else: criteria

    # Same postcode
    criteria = if venue1.postcode && venue2.postcode && venue1.postcode == venue2.postcode do
      ["same_postcode" | criteria]
    else
      criteria
    end

    # Same city
    criteria = if venue1.city_id && venue2.city_id && venue1.city_id == venue2.city_id do
      ["same_city" | criteria]
    else
      criteria
    end

    # Geographic proximity
    geo_sim = calculate_geographic_similarity(venue1, venue2)
    criteria = if geo_sim >= 0.8, do: ["geographic_proximity" | criteria], else: criteria

    # Same Google Place ID
    criteria = if venue1.place_id && venue2.place_id && venue1.place_id == venue2.place_id do
      ["same_place_id" | criteria]
    else
      criteria
    end

    Enum.reverse(criteria)
  end

  # Safe conversion to float for both Decimal and numeric types
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n
end

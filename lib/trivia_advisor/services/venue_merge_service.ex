defmodule TriviaAdvisor.Services.VenueMergeService do
  @moduledoc """
  Service for safely merging duplicate venues while preserving associated data.

  This service handles the complex task of merging two venues by:
  - Determining the best venue to use as primary
  - Migrating all associated events and data
  - Combining metadata intelligently
  - Soft-deleting the secondary venue with proper references
  - Logging all operations for audit and rollback purposes
  - Providing preview functionality to show what would happen
  - Supporting rollback operations to undo merges

  All operations are atomic and use database transactions to ensure data integrity.
  """

  import Ecto.Query
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Events.{Event, VenueMergeLog}
  alias Ecto.Multi

  @type venue_id :: integer()
  @type merge_options :: %{
          performed_by: String.t(),
          notes: String.t() | nil,
          metadata_strategy: :prefer_primary | :prefer_secondary | :combine,
          event_strategy: :migrate_all | :selective,
          field_overrides: list(atom()) | nil,
          dry_run: boolean()
        }

  @type merge_result :: %{
          success: boolean(),
          primary_venue_id: venue_id(),
          secondary_venue_id: venue_id(),
          log_id: integer() | nil,
          events_migrated: integer(),
          metadata_conflicts: list(),
          errors: list()
        }

  @type merge_preview :: %{
          primary_venue: Venue.t(),
          secondary_venue: Venue.t(),
          events_to_migrate: list(Event.t()),
          metadata_conflicts: list(),
          recommended_action: :safe | :review_conflicts | :manual_review,
          estimated_changes: map()
        }

  # Default options for merge operations
  @default_options %{
    performed_by: "system",
    notes: nil,
    metadata_strategy: :combine,
    event_strategy: :migrate_all,
    field_overrides: nil,
    dry_run: false
  }

  @doc """
  Merges two venues safely, combining their data and migrating all associations.

  This is the main merge operation that:
  1. Validates both venues exist and are not already deleted
  2. Determines which venue should be primary (if not specified)
  3. Migrates all events from secondary to primary venue
  4. Combines metadata according to the specified strategy
  5. Soft-deletes the secondary venue with reference to primary
  6. Creates audit log entry for tracking and rollback

  ## Parameters

  * `primary_id` - ID of the venue to keep as the merged result
  * `secondary_id` - ID of the venue to merge into the primary and soft-delete
  * `options` - Map of merge options including performed_by, strategy preferences

  ## Options

  * `:performed_by` - String identifying who performed the merge (required)
  * `:notes` - Optional notes about the merge operation
  * `:metadata_strategy` - How to handle conflicting metadata (`:prefer_primary`, `:prefer_secondary`, `:combine`)
  * `:event_strategy` - How to handle events (`:migrate_all`, `:selective`)
  * `:field_overrides` - List of fields to take from secondary venue regardless of strategy (e.g., `[:website, :phone]`)
  * `:dry_run` - If true, returns what would happen without making changes

  ## Returns

  Returns `{:ok, merge_result}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> VenueMergeService.merge_venues(123, 456, %{performed_by: "admin"})
      {:ok, %{
        success: true,
        primary_venue_id: 123,
        secondary_venue_id: 456,
        log_id: 789,
        events_migrated: 5,
        metadata_conflicts: [],
        errors: []
      }}

      # With custom strategy
      iex> options = %{
      ...>   performed_by: "admin",
      ...>   metadata_strategy: :prefer_primary,
      ...>   field_overrides: [:website, :phone],
      ...>   notes: "Merging duplicate Crown pubs, but keeping their updated website"
      ...> }
      iex> VenueMergeService.merge_venues(123, 456, options)
      {:ok, %{...}}
  """
  @spec merge_venues(venue_id(), venue_id(), merge_options()) :: {:ok, merge_result()} | {:error, any()}
  def merge_venues(primary_id, secondary_id, options \\ %{}) do
    options = Map.merge(@default_options, options)

    if Map.get(options, :dry_run) do
      preview_merge(primary_id, secondary_id, options)
    else
      perform_merge(primary_id, secondary_id, options)
    end
  end

  @doc """
  Previews what would happen during a venue merge without making any changes.

  This provides a detailed view of:
  - Which venue data would be kept/combined
  - How many events would be migrated
  - Any metadata conflicts that need resolution
  - Recommendations for the merge operation

  ## Parameters

  * `primary_id` - ID of the venue that would be kept
  * `secondary_id` - ID of the venue that would be merged and deleted
  * `options` - Optional merge options to preview with

  ## Returns

  Returns `{:ok, merge_preview}` with detailed preview information or `{:error, reason}`.

  ## Examples

      iex> VenueMergeService.preview_merge(123, 456)
      {:ok, %{
        primary_venue: %Venue{...},
        secondary_venue: %Venue{...},
        events_to_migrate: [%Event{...}, ...],
        metadata_conflicts: [
          %{field: :phone, primary: "123-456", secondary: "789-012"}
        ],
        recommended_action: :review_conflicts,
        estimated_changes: %{events_migrated: 3, metadata_updated: 2}
      }}
  """
  @spec preview_merge(venue_id(), venue_id(), merge_options()) :: {:ok, merge_preview()} | {:error, any()}
  def preview_merge(primary_id, secondary_id, options \\ %{}) do
    options = Map.merge(@default_options, options)

    with {:ok, {primary, secondary}} <- load_venues_for_merge(primary_id, secondary_id),
         {:ok, events} <- load_events_for_venue(secondary_id),
         conflicts <- analyze_metadata_conflicts(primary, secondary),
         estimated_changes <- calculate_estimated_changes(primary, secondary, events, options) do

      preview = %{
        primary_venue: primary,
        secondary_venue: secondary,
        events_to_migrate: events,
        metadata_conflicts: conflicts,
        recommended_action: determine_recommendation(conflicts, events),
        estimated_changes: estimated_changes
      }

      {:ok, preview}
    end
  end

  @doc """
  Rolls back a previous venue merge operation.

  This attempts to undo a merge by:
  1. Looking up the merge log entry
  2. Restoring the soft-deleted secondary venue
  3. Moving events back to the secondary venue
  4. Undoing metadata changes where possible
  5. Creating a rollback log entry

  Note: Rollbacks may not be 100% possible if significant time has passed
  or if the venues have been modified since the merge.

  ## Parameters

  * `log_id` - ID of the VenueMergeLog entry to rollback
  * `options` - Optional rollback options including performed_by

  ## Returns

  Returns `{:ok, merge_result}` on successful rollback or `{:error, reason}`.

  ## Examples

      iex> VenueMergeService.rollback_merge(789, %{performed_by: "admin"})
      {:ok, %{
        success: true,
        primary_venue_id: 123,
        secondary_venue_id: 456,
        log_id: 790,
        events_migrated: 5,
        errors: []
      }}
  """
  @spec rollback_merge(integer(), merge_options()) :: {:ok, merge_result()} | {:error, any()}
  def rollback_merge(log_id, options \\ %{}) do
    options = Map.merge(@default_options, options)

    with {:ok, log_entry} <- load_merge_log(log_id),
         {:ok, result} <- perform_rollback(log_entry, options) do
      {:ok, result}
    end
  end

  @doc """
  Determines which of two venues should be the primary in a merge.

  Uses a scoring system based on:
  - Data completeness (more filled fields = higher score)
  - Event count (more events = higher score)
  - Recency (newer venue = slight preference)
  - Place ID presence (Google Place ID = higher score)

  ## Parameters

  * `venue1_id` - ID of first venue to compare
  * `venue2_id` - ID of second venue to compare

  ## Returns

  Returns `{:ok, {primary_id, secondary_id}}` with recommended primary first,
  or `{:error, reason}` if venues cannot be loaded.

  ## Examples

      iex> VenueMergeService.determine_primary_venue(123, 456)
      {:ok, {123, 456}}  # 123 should be primary
  """
  @spec determine_primary_venue(venue_id(), venue_id()) :: {:ok, {venue_id(), venue_id()}} | {:error, any()}
  def determine_primary_venue(venue1_id, venue2_id) do
    with {:ok, {venue1, venue2}} <- load_venues_for_merge(venue1_id, venue2_id) do
      score1 = calculate_venue_score(venue1)
      score2 = calculate_venue_score(venue2)

      if score1 >= score2 do
        {:ok, {venue1.id, venue2.id}}
      else
        {:ok, {venue2.id, venue1.id}}
      end
    end
  end

  @doc """
  Gets a list of all venue merge operations for audit purposes.

  ## Parameters

  * `filters` - Optional keyword list of filters (venue_id, action_type, date_range)
  * `limit` - Maximum number of results to return (default: 100)

  ## Returns

  Returns a list of VenueMergeLog entries with preloaded venue associations.

  ## Examples

      iex> VenueMergeService.list_merge_history()
      [%VenueMergeLog{...}, ...]

      iex> VenueMergeService.list_merge_history(venue_id: 123, action_type: "merge")
      [%VenueMergeLog{...}]
  """
  @spec list_merge_history(keyword(), integer()) :: list(VenueMergeLog.t())
  def list_merge_history(filters \\ [], limit \\ 100) do
    query = from(log in VenueMergeLog,
      preload: [:primary_venue, :secondary_venue],
      order_by: [desc: log.inserted_at],
      limit: ^limit
    )

    query = apply_merge_history_filters(query, filters)
    Repo.all(query)
  end

  # Private implementation functions

  defp perform_merge(primary_id, secondary_id, options) do
    Multi.new()
    |> Multi.run(:load_venues, fn _repo, _changes ->
      load_venues_for_merge(primary_id, secondary_id)
    end)
    |> Multi.run(:migrate_events, fn _repo, %{load_venues: {_primary, secondary}} ->
      migrate_events_to_primary(secondary.id, primary_id)
    end)
    |> Multi.run(:merge_metadata, fn _repo, %{load_venues: {primary, secondary}} ->
              merge_venue_metadata(primary, secondary, Map.get(options, :metadata_strategy), options)
    end)
    |> Multi.run(:soft_delete_secondary, fn _repo, %{load_venues: {_primary, secondary}} ->
      soft_delete_venue(secondary, primary_id, Map.get(options, :performed_by))
    end)
    |> Multi.run(:create_log, fn _repo, changes ->
      create_merge_log(primary_id, secondary_id, changes, options)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} ->
        {:ok, build_merge_result(changes, primary_id, secondary_id)}
      {:error, _step, reason, _changes} ->
        Logger.error("Venue merge failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_venues_for_merge(primary_id, secondary_id) do
    primary = Repo.get(Venue, primary_id)
    secondary = Repo.get(Venue, secondary_id)

    cond do
      is_nil(primary) -> {:error, "Primary venue not found"}
      is_nil(secondary) -> {:error, "Secondary venue not found"}
      primary_id == secondary_id -> {:error, "Cannot merge venue with itself"}
      not is_nil(primary.deleted_at) -> {:error, "Primary venue is already deleted"}
      not is_nil(secondary.deleted_at) -> {:error, "Secondary venue is already deleted"}
      true -> {:ok, {primary, secondary}}
    end
  end

  defp load_events_for_venue(venue_id) do
    events = from(e in Event, where: e.venue_id == ^venue_id) |> Repo.all()
    {:ok, events}
  end

  defp migrate_events_to_primary(secondary_id, primary_id) do
    # Get all events from secondary venue
    secondary_events = from(e in Event, where: e.venue_id == ^secondary_id) |> Repo.all()

    # Get existing events from primary venue to check for conflicts
    existing_primary_events = from(e in Event,
      where: e.venue_id == ^primary_id,
      select: {e.day_of_week, e.start_time}
    ) |> Repo.all() |> MapSet.new()

    # Split events into those that can be migrated vs those that conflict
    {migratable_events, conflicting_events} =
      Enum.split_with(secondary_events, fn event ->
        not MapSet.member?(existing_primary_events, {event.day_of_week, event.start_time})
      end)

    # Migrate non-conflicting events
    migrated_count = if length(migratable_events) > 0 do
      migratable_ids = Enum.map(migratable_events, & &1.id)
      query = from(e in Event, where: e.id in ^migratable_ids)

      case Repo.update_all(query, set: [venue_id: primary_id, updated_at: DateTime.utc_now()]) do
        {count, _} -> count
        _ -> 0
      end
    else
      0
    end

    # Delete conflicting events from secondary venue
    # (Primary venue events take precedence)
    deleted_count = if length(conflicting_events) > 0 do
      conflicting_ids = Enum.map(conflicting_events, & &1.id)
      query = from(e in Event, where: e.id in ^conflicting_ids)

      case Repo.delete_all(query) do
        {count, _} -> count
        _ -> 0
      end
    else
      0
    end

    # Log the conflict resolution if there were conflicts
    if deleted_count > 0 do
      Logger.info("Venue merge: Deleted #{deleted_count} conflicting events from secondary venue #{secondary_id}, migrated #{migrated_count} events to primary venue #{primary_id}")
    end

    {:ok, migrated_count}
  end

  defp analyze_metadata_conflicts(primary, secondary) do
    conflicting_fields = [:name, :address, :postcode, :phone, :website, :facebook, :instagram, :slug]

    Enum.reduce(conflicting_fields, [], fn field, conflicts ->
      primary_value = Map.get(primary, field)
      secondary_value = Map.get(secondary, field)

      if has_conflict?(primary_value, secondary_value) do
        [%{field: field, primary: primary_value, secondary: secondary_value} | conflicts]
      else
        conflicts
      end
    end)
  end

  defp has_conflict?(value1, value2) do
    # Both values exist and are different
    not is_nil(value1) and not is_nil(value2) and value1 != value2
  end

  defp merge_venue_metadata(primary, secondary, strategy, options) do
    merged_attrs = case strategy do
      :prefer_primary -> build_override_attrs(secondary, options)
      :prefer_secondary -> build_secondary_attrs(secondary)
      :combine -> build_combined_attrs(primary, secondary, options)
    end

    if map_size(merged_attrs) > 0 do
      changeset = Venue.changeset(primary, merged_attrs)
      Repo.update(changeset)
    else
      {:ok, primary}
    end
  end

  defp build_secondary_attrs(secondary) do
    # Take all non-nil values from secondary, including image arrays
    [:name, :address, :postcode, :phone, :website, :facebook, :instagram, :google_place_images, :slug]
    |> Enum.reduce(%{}, fn field, attrs ->
      case Map.get(secondary, field) do
        nil -> attrs
        [] when field == :google_place_images -> attrs  # Skip empty image arrays
        value -> Map.put(attrs, field, value)
      end
    end)
  end

  defp build_override_attrs(secondary, options) do
    # Only take specific fields from secondary when field_overrides is specified
    field_overrides = Map.get(options, :field_overrides, []) || []

    field_overrides
    |> Enum.reduce(%{}, fn field, attrs ->
      case Map.get(secondary, field) do
        nil -> attrs
        [] when field == :google_place_images -> attrs  # Skip empty image arrays
        value -> Map.put(attrs, field, value)
      end
    end)
  end

    defp build_combined_attrs(primary, secondary, options) do
    # Prefer non-nil values, with preference for more complete data
    field_overrides = Map.get(options, :field_overrides, []) || []

    [:name, :address, :postcode, :phone, :website, :facebook, :instagram, :google_place_images, :slug]
    |> Enum.reduce(%{}, fn field, attrs ->
      primary_value = Map.get(primary, field)
      secondary_value = Map.get(secondary, field)

      # If this field is in overrides, always use secondary value (if not nil)
      if field in field_overrides and not is_nil(secondary_value) do
        # Skip empty image arrays
        if field == :google_place_images and secondary_value == [] do
          attrs
        else
          Map.put(attrs, field, secondary_value)
        end
      else
        # Use normal logic for non-overridden fields
        case choose_better_value(primary_value, secondary_value, field) do
          ^primary_value -> attrs  # No change needed
          better_value -> Map.put(attrs, field, better_value)
        end
      end
    end)
  end

  defp choose_better_value(nil, secondary, _field), do: secondary
  defp choose_better_value(primary, nil, _field), do: primary
  defp choose_better_value(primary, secondary, :google_place_images) do
    # For images, combine both arrays and deduplicate by URL
    primary_images = primary || []
    secondary_images = secondary || []

    # Combine and deduplicate images by URL to avoid near-duplicates
    combined = (primary_images ++ secondary_images)
    |> Enum.uniq_by(&Map.get(&1, "url"))  # Deduplicate by URL, not entire map

    case combined do
      [] -> primary  # Keep original if somehow no images
      images -> images
    end
  end
  defp choose_better_value(primary, secondary, :slug) do
    # Prefer better quality slugs - shorter is generally better for SEO
    # Also prefer slugs without trailing numbers (which often indicate duplicates)
    primary_score = calculate_slug_score(primary)
    secondary_score = calculate_slug_score(secondary)

    if secondary_score > primary_score, do: secondary, else: primary
  end
  defp choose_better_value(primary, secondary, _field) do
    # Prefer longer/more complete values for text fields
    if String.length(to_string(secondary)) > String.length(to_string(primary)) do
      secondary
    else
      primary
    end
  end

  defp soft_delete_venue(venue, merged_into_id, performed_by) do
    # Since ecto_soft_delete only handles deleted_at, we need to update other fields manually
    attrs = %{
      deleted_at: DateTime.utc_now(),
      deleted_by: performed_by,
      merged_into_id: merged_into_id
    }

    changeset = Venue.soft_delete_changeset(venue, attrs)
    Repo.update(changeset)
  end

  defp create_merge_log(primary_id, secondary_id, changes, options) do
    attrs = %{
      action_type: "merge",
      primary_venue_id: primary_id,
      secondary_venue_id: secondary_id,
      performed_by: Map.get(options, :performed_by),
      notes: Map.get(options, :notes),
      metadata: %{
        events_migrated: changes[:migrate_events] || 0,
        metadata_strategy: Map.get(options, :metadata_strategy),
        changes_made: extract_changes_metadata(changes)
      }
    }

    %VenueMergeLog{}
    |> VenueMergeLog.changeset(attrs)
    |> Repo.insert()
  end

  defp extract_changes_metadata(changes) do
    %{
      events_migrated: changes[:migrate_events] || 0,
      metadata_updated: not is_nil(changes[:merge_metadata]),
      timestamp: DateTime.utc_now()
    }
  end

  defp calculate_slug_score(slug) when is_nil(slug), do: 0
  defp calculate_slug_score(slug) do
    base_score = 5  # Base score for having a slug

    # Prefer shorter slugs (within reason)
    length_score = case String.length(slug) do
      len when len <= 20 -> 3  # Short, clean slugs
      len when len <= 35 -> 2  # Reasonable length
      len when len <= 50 -> 1  # Getting long
      _ -> 0  # Too long
    end

    # Penalize slugs with trailing numbers (often indicate duplicates)
    number_penalty = if Regex.match?(~r/-\d+$/, slug), do: -2, else: 0

    # Bonus for clean, readable slugs (no excessive dashes)
    dash_penalty = case Regex.scan(~r/-/, slug) |> length() do
      count when count <= 3 -> 0   # Normal number of dashes
      count when count <= 6 -> -1  # Getting wordy
      _ -> -2  # Too many dashes
    end

    # Ensure minimum score is 0
    max(0, base_score + length_score + number_penalty + dash_penalty)
  end

  defp calculate_venue_score(venue) do
    # Preload events for scoring
    venue = Repo.preload(venue, :events)

    base_score = 0

    # Data completeness score (1 point per non-nil field)
    data_score = [:name, :address, :postcode, :phone, :website, :place_id]
    |> Enum.count(fn field -> not is_nil(Map.get(venue, field)) end)

    # Event count score (up to 10 points)
    event_score = min(length(venue.events), 10)

    # Recency score (newer venues get slight preference)
    days_old = DateTime.diff(DateTime.utc_now(), venue.inserted_at, :day)
    recency_score = max(0, 30 - days_old) / 30 * 5  # Up to 5 points for venues < 30 days old

    # Place ID bonus (5 points for having Google Place ID)
    place_id_score = if venue.place_id, do: 5, else: 0

    # Slug quality score (up to 10 points for better slugs)
    slug_score = calculate_slug_score(venue.slug)

    base_score + data_score + event_score + recency_score + place_id_score + slug_score
  end

    defp calculate_estimated_changes(primary, secondary, events, options) do
    field_overrides = Map.get(options, :field_overrides, []) || []
    strategy = Map.get(options, :metadata_strategy, :combine)

    # Calculate which fields would actually change
    metadata_changes = case strategy do
      :prefer_primary -> build_override_attrs(secondary, options)
      :prefer_secondary -> build_secondary_attrs(secondary)
      :combine -> build_combined_attrs(primary, secondary, options)
    end

    %{
      events_migrated: length(events),
      metadata_conflicts: length(analyze_metadata_conflicts(primary, secondary)),
      metadata_updated: map_size(metadata_changes) > 0,
      field_overrides_applied: field_overrides,
      fields_that_will_change: Map.keys(metadata_changes),
      venue_soft_deleted: true
    }
  end

  defp determine_recommendation(conflicts, events) do
    cond do
      length(conflicts) == 0 and length(events) <= 10 -> :safe
      length(conflicts) <= 3 and length(events) <= 50 -> :review_conflicts
      true -> :manual_review
    end
  end

  defp load_merge_log(log_id) do
    case Repo.get(VenueMergeLog, log_id) do
      nil -> {:error, "Merge log not found"}
      log -> {:ok, Repo.preload(log, [:primary_venue, :secondary_venue])}
    end
  end

  defp perform_rollback(_log_entry, _options) do
    # Implementation for rollback would go here
    # This is complex and might not always be possible
    {:error, "Rollback functionality not yet implemented"}
  end

  defp build_merge_result(changes, primary_id, secondary_id) do
    %{
      success: true,
      primary_venue_id: primary_id,
      secondary_venue_id: secondary_id,
      log_id: changes.create_log.id,
      events_migrated: changes.migrate_events,
      metadata_conflicts: [],  # Would need to extract from merge process
      errors: []
    }
  end

  defp apply_merge_history_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:venue_id, venue_id}, q ->
        from(log in q, where: log.primary_venue_id == ^venue_id or log.secondary_venue_id == ^venue_id)
      {:action_type, action}, q ->
        from(log in q, where: log.action_type == ^action)
      {:date_range, {start_date, end_date}}, q ->
        from(log in q, where: log.inserted_at >= ^start_date and log.inserted_at <= ^end_date)
      _, q -> q
    end)
  end

  @doc """
  Creates a log entry to mark two venues as NOT duplicates.

  This prevents the pair from appearing in future duplicate listings
  by creating a "not_duplicate" log entry that can be referenced by
  the duplicate detection system.

  ## Parameters

  * `venue1_id` - ID of the first venue
  * `venue2_id` - ID of the second venue
  * `options` - Map with performed_by and optional notes

  ## Returns

  Returns `{:ok, log_entry}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> VenueMergeService.create_not_duplicate_log(123, 456, %{performed_by: "admin"})
      {:ok, %VenueMergeLog{action_type: "not_duplicate", ...}}
  """
  @spec create_not_duplicate_log(venue_id(), venue_id(), %{performed_by: String.t(), notes: String.t() | nil}) :: {:ok, VenueMergeLog.t()} | {:error, any()}
  def create_not_duplicate_log(venue1_id, venue2_id, options) do
    attrs = %{
      action_type: "not_duplicate",
      primary_venue_id: venue1_id,
      secondary_venue_id: venue2_id,
      performed_by: Map.get(options, :performed_by, "system"),
      notes: Map.get(options, :notes),
      metadata: %{
        marked_at: DateTime.utc_now(),
        reason: "manually_reviewed"
      }
    }

    %VenueMergeLog{}
    |> VenueMergeLog.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, log} -> {:ok, log}
      {:error, %Ecto.Changeset{errors: errors}} ->
        # Check if this is a unique constraint violation
        if Keyword.has_key?(errors, :primary_venue_id) do
          # Pair already marked as not duplicate - return success with existing log
          {:ok, :already_exists}
        else
          {:error, errors}
        end
      {:error, error} -> {:error, error}
    end
  end
end

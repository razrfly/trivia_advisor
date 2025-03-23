defmodule TriviaAdvisor.Scraping.Helpers.JobMetadata do
  @moduledoc """
  Helper module for standardizing job metadata across different scraper jobs.

  This provides a consistent way to update metadata for Oban jobs, which
  can be useful for debugging, reporting, and tracking job progress.
  """

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Events.EventSource

  @doc """
  Updates the metadata for an index job (scraper that lists venues/events).

  ## Parameters
    * `job_id` - The ID of the Oban job
    * `metadata` - A map containing the metadata to store
    * `opts` - Optional keyword list of options

  ## Example
      JobMetadata.update_index_job(job_id, %{
        total_count: 100,
        processed_count: 50,
        source_id: 1
      })
  """
  def update_index_job(job_id, metadata, opts \\ [])
  def update_index_job(nil, _metadata, _opts), do: :ok
  def update_index_job(job_id, metadata, opts) do
    base_metadata = %{
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Convert atom keys to strings if needed
    normalized_metadata = normalize_keys(metadata)

    # Merge with any existing metadata if requested
    final_metadata = if Keyword.get(opts, :merge, false) do
      existing_metadata = get_existing_metadata(job_id)
      Map.merge(existing_metadata, Map.merge(base_metadata, normalized_metadata))
    else
      Map.merge(base_metadata, normalized_metadata)
    end

    # Update the job's metadata
    Repo.update_all(
      from(j in "oban_jobs", where: j.id == ^job_id),
      set: [meta: final_metadata]
    )

    :ok
  end

  @doc """
  Updates the metadata for a detail job (scraper that processes a single venue/event).

  ## Parameters
    * `job_id` - The ID of the Oban job
    * `venue_data` - Map containing venue data
    * `result` - The processing result
    * `opts` - Optional keyword list of options

  ## Example
      JobMetadata.update_detail_job(job_id, venue_data, result)
  """
  def update_detail_job(job_id, venue_data, result, opts \\ [])
  def update_detail_job(nil, _venue_data, _result, _opts), do: :ok
  def update_detail_job(job_id, venue_data, result, opts) do
    # Debug what we're getting
    Logger.debug("📊 JobMetadata.update_detail_job called with: job_id=#{job_id}, venue_data=#{inspect(venue_data)}, result=#{inspect(result)}")

    # Simply normalize the raw venue data
    normalized_venue_data = normalize_keys(venue_data)

    # Safely extract the result status without accessing tuple properties directly
    result_status = cond do
      is_tuple(result) && tuple_size(result) == 2 && elem(result, 0) == :ok -> "success"
      is_tuple(result) && tuple_size(result) == 2 && elem(result, 0) == :error -> "error"
      is_map(result) -> "success"  # If a map was passed directly, consider it success
      true -> "unknown"
    end

    # Add timestamp and status
    metadata = Map.merge(normalized_venue_data, %{
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "result_status" => result_status
    })

    # Merge with any existing metadata if requested
    final_metadata = if Keyword.get(opts, :merge, false) do
      existing_metadata = get_existing_metadata(job_id)
      Map.merge(existing_metadata, metadata)
    else
      metadata
    end

    # Debug what we're storing
    Logger.debug("📊 JobMetadata.update_detail_job storing metadata: #{inspect(final_metadata)}")

    # Update the job's metadata
    Repo.update_all(
      from(j in "oban_jobs", where: j.id == ^job_id),
      set: [meta: final_metadata]
    )

    # If this is a successful job that processed an event, ensure the event source timestamp is updated
    if result_status == "success" and is_tuple(result) and tuple_size(result) == 2 and elem(result, 0) == :ok do
      result_data = elem(result, 1)

      # Extract necessary information - support different result formats
      event_id = cond do
        is_map(result_data) && Map.has_key?(result_data, :event_id) -> result_data.event_id
        is_map(result_data) && Map.has_key?(result_data, "event_id") -> result_data["event_id"]
        true -> nil
      end

      source_id = cond do
        is_map(normalized_venue_data) && Map.has_key?(normalized_venue_data, "source_id") -> normalized_venue_data["source_id"]
        Keyword.keyword?(opts) && Keyword.has_key?(opts, :source_id) -> Keyword.get(opts, :source_id)
        true -> nil
      end

      # Try to get source_id from URL if missing
      source_id = if is_nil(source_id) and Map.has_key?(normalized_venue_data, "url") do
        url = normalized_venue_data["url"]
        find_source_by_url(url)
      else
        source_id
      end

      # If we have an event ID and source ID, ensure the timestamp is updated
      if event_id && source_id do
        Logger.info("🔄 Ensuring event_source last_seen_at is updated for event_id=#{event_id}, source_id=#{source_id}")

        url = Map.get(normalized_venue_data, "url")

        # First try the regular timestamp update with force
        case ensure_event_source_timestamp(event_id, source_id, url, force: true) do
          {:ok, _updated_source} = result ->
            # Success! Nothing more to do
            result

          {:error, _reason} ->
            # If that fails, try the force update as a fallback
            Logger.warning("⚠️ Normal timestamp update failed, trying direct force update")
            force_update_event_source_timestamp(event_id, source_id, url)
        end
      end
    end

    :ok
  end

  @doc """
  Updates the metadata with error information.

  ## Parameters
    * `job_id` - The ID of the Oban job
    * `error` - The error that occurred
    * `opts` - Optional keyword list of options

  ## Example
      JobMetadata.update_error(job_id, error)
  """
  def update_error(job_id, error, opts \\ [])
  def update_error(nil, _error, _opts), do: :ok
  def update_error(job_id, error, opts) do
    # Basic error metadata
    error_metadata = %{
      "error" => inspect(error),
      "error_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "result_status" => "error"
    }

    # Add additional context if provided
    context = Keyword.get(opts, :context, %{})
    error_with_context = Map.merge(error_metadata, normalize_keys(context))

    # Merge with existing metadata if requested
    final_metadata = if Keyword.get(opts, :merge, false) do
      existing_metadata = get_existing_metadata(job_id)
      Map.merge(existing_metadata, error_with_context)
    else
      error_with_context
    end

    # Update the job's metadata
    Repo.update_all(
      from(j in "oban_jobs", where: j.id == ^job_id),
      set: [meta: final_metadata]
    )

    :ok
  end

  @doc """
  Ensures the event source's last_seen_at timestamp is updated.
  This function guarantees that whenever a scraper job succeeds,
  the event source timestamp is always updated.

  ## Parameters
    * `event_id` - The ID of the event
    * `source_id` - The ID of the source
    * `source_url` - The source URL (optional)
    * `opts` - Options including:
       * `:force` - Force update even if other values don't match
       * `:retry` - Number of retries (default: 1)

  ## Returns
    * `{:ok, event_source}` - If the event source was found and updated
    * `{:error, reason}` - If there was an error updating the event source
  """
  def ensure_event_source_timestamp(event_id, source_id, source_url \\ nil, opts \\ []) do
    now = DateTime.utc_now()
    force = Keyword.get(opts, :force, false)
    retries = Keyword.get(opts, :retry, 1)

    Logger.info("🕒 Ensuring event_source last_seen_at is updated to #{DateTime.to_string(now)}")
    Logger.info("🔧 Options: force=#{force}, retries=#{retries}")

    # Find all matching event sources - this handles cases where there might be multiple
    # due to data inconsistencies
    event_sources = Repo.all(
      from es in EventSource,
      where: es.event_id == ^event_id and es.source_id == ^source_id
    )

    case event_sources do
      [] ->
        error_msg = "❌ No event source found for event_id=#{event_id}, source_id=#{source_id}"
        Logger.error(error_msg)

        if force do
          # If forcing, try to create a new event source
          Logger.warning("⚠️ Force flag set. Attempting to create a new event source.")
          try_create_event_source(event_id, source_id, source_url, now)
        else
          {:error, :event_source_not_found}
        end

      event_sources ->
        # Update all matching event sources - normally just one
        Logger.info("🔄 Found #{length(event_sources)} event source(s) to update")

        Repo.transaction(fn ->
          Enum.map(event_sources, fn event_source ->
            update_event_source_timestamp(event_source, source_url, now, force)
          end)
        end)
        |> handle_transaction_result(event_id, source_id, source_url, now, retries, force)
    end
  end

  # Helper function to handle transaction results with retry logic
  defp handle_transaction_result(result, event_id, source_id, source_url, now, retries, force) do
    case result do
      {:ok, updated_sources} ->
        {:ok, List.first(updated_sources)}

      {:error, reason} ->
        Logger.error("❌ Transaction failed: #{inspect(reason)}")

        if retries > 0 do
          Logger.warning("⚠️ Retrying timestamp update (#{retries} retries left)")
          :timer.sleep(500) # Small delay before retry
          ensure_event_source_timestamp(event_id, source_id, source_url, [force: force, retry: retries - 1])
        else
          Logger.error("❌ All retries failed for timestamp update")
          {:error, reason}
        end
    end
  end

  # Helper function to update a single event source's timestamp
  defp update_event_source_timestamp(event_source, source_url, now, force) do
    # Build update params
    update_params = %{last_seen_at: now}

    # Add source_url if provided and different from current
    update_params = if not is_nil(source_url) and source_url != event_source.source_url do
      Logger.info("🔄 Updating source_url from '#{event_source.source_url}' to '#{source_url}'")
      Map.put(update_params, :source_url, source_url)
    else
      update_params
    end

    # Log detailed before-update state
    Logger.info("🔍 Before update - event_source #{event_source.id}:")
    Logger.info("   - last_seen_at: #{DateTime.to_string(event_source.last_seen_at)}")
    Logger.info("   - source_url: #{event_source.source_url}")

    # Update the event source
    result = event_source
    |> EventSource.changeset(update_params)
    |> Repo.update()

    case result do
      {:ok, updated_source} ->
        # Verify the update was actually applied
        if DateTime.compare(updated_source.last_seen_at, event_source.last_seen_at) == :gt or force do
          Logger.info("✅ Successfully updated event_source #{updated_source.id} last_seen_at to #{DateTime.to_string(updated_source.last_seen_at)}")
          updated_source
        else
          Logger.error("⚠️ Timestamp not updated despite successful DB operation!")
          if force do
            Logger.warning("⚠️ Force flag set. Attempting direct update.")
            # Direct update as a last resort when force is true
            {:ok, forced_update} = Repo.update_all(
              from(es in EventSource, where: es.id == ^event_source.id),
              set: [last_seen_at: now, updated_at: now]
            )
            Logger.info("🔨 Forced update completed: #{inspect(forced_update)}")
            # Refetch to get the updated record
            Repo.get(EventSource, event_source.id)
          else
            Repo.rollback({:error, :timestamp_not_updated})
          end
        end
      {:error, changeset} ->
        Logger.error("❌ Failed to update event_source #{event_source.id}: #{inspect(changeset.errors)}")
        Repo.rollback({:error, changeset})
    end
  end

  # Try to create a new event source if none found (used with force flag)
  defp try_create_event_source(event_id, source_id, source_url, now) do
    event = Repo.get(TriviaAdvisor.Events.Event, event_id)

    if event do
      # Build minimal metadata
      metadata = %{
        raw_title: event.name,
        clean_title: event.name,
        day_of_week: event.day_of_week,
        start_time: event.start_time,
        frequency: event.frequency
      }

      %EventSource{}
      |> EventSource.changeset(%{
        event_id: event_id,
        source_id: source_id,
        source_url: source_url || "https://unknown-source-url.com",
        metadata: metadata,
        last_seen_at: now
      })
      |> Repo.insert()
      |> case do
        {:ok, event_source} ->
          Logger.info("✅ Successfully created new event_source #{event_source.id} with force flag")
          {:ok, event_source}
        {:error, changeset} ->
          Logger.error("❌ Failed to create event_source with force flag: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    else
      Logger.error("❌ Cannot create event source because event #{event_id} does not exist")
      {:error, :event_not_found}
    end
  end

  # Helper function to find a source ID from a URL
  defp find_source_by_url(url) when is_binary(url) do
    # Check for common patterns in URLs
    cond do
      String.contains?(url, "quizmeisters.com") or String.contains?(url, "quizmeisters.com.au") ->
        # Try to find the Quizmeisters source
        source = Repo.one(
          from s in TriviaAdvisor.Scraping.Source,
          where: like(s.website_url, "%quizmeisters%")
        )
        if source, do: source.id, else: nil

      String.contains?(url, "questionone.com") ->
        # Try to find the QuestionOne source
        source = Repo.one(
          from s in TriviaAdvisor.Scraping.Source,
          where: like(s.website_url, "%questionone%")
        )
        if source, do: source.id, else: nil

      true ->
        nil
    end
  end
  defp find_source_by_url(_), do: nil

  # Helper function to retrieve existing metadata for a job
  defp get_existing_metadata(job_id) do
    query = from j in "oban_jobs",
            where: j.id == ^job_id,
            select: j.meta
    case Repo.one(query) do
      nil -> %{}
      metadata -> metadata
    end
  end

  # Helper function to normalize keys in a map
  defp normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      key = to_string(k)
      Map.put(acc, key, v)
    end)
  end
  defp normalize_keys(non_map), do: non_map

  @doc """
  Force updates the event source's last_seen_at timestamp using a direct SQL update.
  This function is a last resort when the regular timestamp update mechanism fails.

  ## Parameters
    * `event_id` - The ID of the event
    * `source_id` - The ID of the source
    * `source_url` - The source URL (optional)

  ## Returns
    * `{:ok, updated_count}` - If the event source(s) were updated
    * `{:error, reason}` - If there was an error updating the event source
  """
  def force_update_event_source_timestamp(event_id, source_id, source_url \\ nil) do
    now = DateTime.utc_now()
    Logger.warning("🔨 Forcing event_source last_seen_at update to #{DateTime.to_string(now)}")

    # Get the event source IDs
    event_sources = Repo.all(
      from es in EventSource,
      where: es.event_id == ^event_id and es.source_id == ^source_id,
      select: es.id
    )

    if event_sources == [] do
      Logger.error("❌ No event source found for event_id=#{event_id}, source_id=#{source_id}")
      {:error, :event_source_not_found}
    else
      Logger.info("🔄 Found #{length(event_sources)} event source IDs: #{inspect(event_sources)}")

      # First try normal Ecto update_all
      {updated_count, _} = Repo.update_all(
        from(es in EventSource, where: es.id in ^event_sources),
        set: [
          last_seen_at: now,
          updated_at: now
        ]
      )

      if updated_count > 0 do
        Logger.info("✅ Successfully force-updated #{updated_count} event sources via Ecto.update_all")

        # Also update source_url if provided
        if source_url do
          {url_updated, _} = Repo.update_all(
            from(es in EventSource, where: es.id in ^event_sources),
            set: [source_url: source_url]
          )
          Logger.info("✅ Updated source_url for #{url_updated} event sources")
        end

        # For verification, get the first updated event source
        updated_source = Repo.get(EventSource, List.first(event_sources))

        # Verify the update worked
        if DateTime.compare(updated_source.last_seen_at, now) == :eq do
          Logger.info("✅ Verification - event_source #{updated_source.id} last_seen_at now: #{DateTime.to_string(updated_source.last_seen_at)}")
          {:ok, updated_count}
        else
          # If verification fails, try direct SQL as a last resort
          Logger.warning("⚠️ Ecto update verified but timestamp mismatch, trying direct SQL")
          force_update_with_sql(event_sources, now, source_url)
        end
      else
        Logger.error("❌ Failed to force-update any event sources via Ecto")
        # Try direct SQL as a fallback
        force_update_with_sql(event_sources, now, source_url)
      end
    end
  end

  # Helper for direct SQL timestamp update - the nuclear option
  defp force_update_with_sql(event_source_ids, now, source_url) do
    Logger.warning("☢️ Using direct SQL update (nuclear option) for event source timestamps")

    # Convert event source IDs to array if there's more than one
    ids_str = if length(event_source_ids) > 1 do
      ids = Enum.join(event_source_ids, ",")
      "(#{ids})"
    else
      List.first(event_source_ids)
    end

    # Build SQL query for timestamp update
    sql = "UPDATE event_sources SET last_seen_at = $1, updated_at = $2 WHERE id IN (#{ids_str})"
    params = [now, now]

    # Execute SQL query
    case Ecto.Adapters.SQL.query(Repo, sql, params) do
      {:ok, result} ->
        Logger.info("✅ SQL update successful: #{inspect(result.num_rows)} rows affected")

        # Also update source_url if provided
        if source_url do
          url_sql = "UPDATE event_sources SET source_url = $1 WHERE id IN (#{ids_str})"
          case Ecto.Adapters.SQL.query(Repo, url_sql, [source_url]) do
            {:ok, url_result} ->
              Logger.info("✅ SQL source_url update successful: #{inspect(url_result.num_rows)} rows affected")
            {:error, error} ->
              Logger.error("❌ SQL source_url update failed: #{inspect(error)}")
          end
        end

        # Verify update
        updated_source = Repo.get(EventSource, List.first(event_source_ids))
        Logger.info("✅ Verification - event_source #{updated_source.id} last_seen_at now: #{DateTime.to_string(updated_source.last_seen_at)}")

        {:ok, result.num_rows}
      {:error, error} ->
        Logger.error("❌ SQL update failed: #{inspect(error)}")
        {:error, error}
    end
  end
end

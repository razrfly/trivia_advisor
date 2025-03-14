defmodule TriviaAdvisor.Scraping.Helpers.JobMetadata do
  @moduledoc """
  Helper module for standardizing job metadata across different scraper jobs.

  This provides a consistent way to update metadata for Oban jobs, which
  can be useful for debugging, reporting, and tracking job progress.
  """

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo

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
    # Extract venue data as is - do minimal transformations to preserve original behavior
    normalized_venue_data = ensure_string_keys(venue_data)

    # Extract relevant data from the processing result
    {status, _} = extract_result_data(result)

    # Base metadata that's common to all detail jobs
    base_metadata = %{
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "result_status" => status
    }

    # Combine with venue data - but don't force any fields that weren't in the original
    # This preserves the original behavior where some fields might be nil
    metadata = Map.merge(base_metadata, normalized_venue_data)

    # Merge with any existing metadata if requested
    final_metadata = if Keyword.get(opts, :merge, false) do
      existing_metadata = get_existing_metadata(job_id)
      Map.merge(existing_metadata, metadata)
    else
      metadata
    end

    # Update the job's metadata
    Repo.update_all(
      from(j in "oban_jobs", where: j.id == ^job_id),
      set: [meta: final_metadata]
    )

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

  # Private helper functions

  # Ensure all keys in a map can be accessed as strings
  # This preserves the original structure while allowing string access
  defp ensure_string_keys(map) when is_map(map) do
    Enum.reduce(map, map, fn {k, _v}, acc ->
      if is_atom(k) do
        Map.put(acc, Atom.to_string(k), Map.get(map, k))
      else
        acc
      end
    end)
  end
  defp ensure_string_keys(value), do: value

  # Extract relevant data from the processing result
  defp extract_result_data(result) do
    case result do
      # Success cases - the original behavior for successful results
      {:ok, _any} ->
        {"success", %{}}

      # Error cases - preserve original behavior
      {:error, reason} ->
        {"error", %{error: reason}}

      # Unexpected format - just return a basic structure
      _ ->
        {"unknown", %{}}
    end
  end

  # Normalize map keys to strings
  defp normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = if is_map(v) && not is_struct(v), do: normalize_keys(v), else: v
      Map.put(acc, key, value)
    end)
  end
  defp normalize_keys(value), do: value

  # Get existing metadata for a job
  defp get_existing_metadata(job_id) do
    case Repo.one(from j in "oban_jobs", where: j.id == ^job_id, select: j.meta) do
      nil -> %{}
      meta -> meta
    end
  end
end

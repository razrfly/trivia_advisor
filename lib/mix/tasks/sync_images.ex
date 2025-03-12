defmodule Mix.Tasks.SyncImages do
  @moduledoc """
  Syncs image files from Tigris cloud storage to local development.

  This task:
  1. Scans the Tigris bucket for image files
  2. Compares against the local filesystem
  3. Only downloads missing files
  4. Avoids processing the same files multiple times
  5. Preserves existing local files

  ## Examples

      # Run a dry run to see what would be downloaded
      mix sync_images --dry-run

      # Perform the actual sync
      mix sync_images

  """
  use Mix.Task
  require Logger

  @shortdoc "Syncs image files from Tigris cloud storage to local development"
  @uploads_dir "priv/static/uploads"
  @max_objects_per_page 1000 # S3 default pagination limit

  @impl Mix.Task
  def run(args) do
    # Process command line arguments
    opts = parse_args(args)

    # Load environment variables from .env file
    load_env_vars()

    # Get Tigris credentials from environment variables
    tigris_access_key_id = System.get_env("TIGRIS_ACCESS_KEY_ID")
    tigris_secret_access_key = System.get_env("TIGRIS_SECRET_ACCESS_KEY")
    tigris_bucket_name = System.get_env("TIGRIS_BUCKET_NAME") || "trivia-app"

    if is_nil(tigris_access_key_id) || is_nil(tigris_secret_access_key) do
      Logger.error("Tigris credentials not found in .env file. Make sure TIGRIS_ACCESS_KEY_ID and TIGRIS_SECRET_ACCESS_KEY are set.")
      exit({:shutdown, 1})
    end

    # Always ensure uploads directory exists
    File.mkdir_p!(@uploads_dir)

    # Start required applications and configure AWS
    ensure_applications_started()
    configure_aws_for_tigris(tigris_access_key_id, tigris_secret_access_key)

    # Create an ETS table to track processed files and stats
    :ets.new(:sync_image_stats, [:set, :public, :named_table])
    :ets.insert(:sync_image_stats, {:processed_keys, MapSet.new()})
    :ets.insert(:sync_image_stats, {:missing_files_count, 0})
    :ets.insert(:sync_image_stats, {:existing_files_count, 0})
    :ets.insert(:sync_image_stats, {:download_count, 0})
    :ets.insert(:sync_image_stats, {:duplicate_checks, 0})
    :ets.insert(:sync_image_stats, {:download_failures, 0})
    :ets.insert(:sync_image_stats, {:total_objects_scanned, 0})

    try do
      Logger.info("Starting image sync process#{if opts[:dry_run], do: " (dry run)", else: ""}...")

      # Only scan specific leaf directories (avoid scanning the problematic uploads/ prefix)
      specific_directories = [
        "uploads/venues/",
        "uploads/google_place_images/",
        "uploads/performers/"
      ]

      Logger.info("Scanning specific directories:")
      Enum.each(specific_directories, &Logger.info("  - #{&1}"))

      # Process each specific directory
      Enum.each(specific_directories, fn prefix ->
        Logger.info("Scanning directory: #{prefix}")

        # Create a directory-specific processor function with the correct arity
        processor = if opts[:dry_run] do
          fn key, local_path -> process_dry_run(key, local_path) end
        else
          fn key, local_path -> process_and_download(key, local_path, tigris_bucket_name) end
        end

        # Scan this directory
        scan_with_pagination(tigris_bucket_name, prefix, nil, processor)
      end)

      # Display stats
      display_stats()

      Logger.info("Image sync completed successfully!")
    rescue
      e ->
        Logger.error("Error syncing images: #{inspect(e, pretty: true, limit: :infinity)}")
        exit({:shutdown, 1})
    after
      # Clean up ETS table
      :ets.delete(:sync_image_stats)
    end
  end

  # Parse command line arguments
  defp parse_args(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [dry_run: :boolean])
    opts
  end

  defp load_env_vars do
    case Code.ensure_loaded(DotenvParser) do
      {:module, _} ->
        DotenvParser.load_file(".env")
      _ ->
        Logger.warning("DotenvParser module not found. Assuming environment variables are already loaded.")
    end
  end

  defp ensure_applications_started do
    # Start required applications for ExAws
    [:hackney, :telemetry, :ex_aws]
    |> Enum.each(fn app ->
      case Application.ensure_all_started(app) do
        {:ok, _} -> :ok
        {:error, {reason, app}} ->
          Logger.warning("Failed to start #{app} application: #{reason}")
      end
    end)
  end

  defp configure_aws_for_tigris(access_key_id, secret_access_key) do
    # Configure ExAws to use Tigris credentials and endpoint
    Application.put_env(:ex_aws, :access_key_id, access_key_id)
    Application.put_env(:ex_aws, :secret_access_key, secret_access_key)

    # Configure S3 endpoint for Tigris
    Application.put_env(:ex_aws, :s3,
      %{
        host: "fly.storage.tigris.dev",
        scheme: "https://",
        region: "auto"
      }
    )
  end

  # Improved pagination handling with a limit on continuation tokens
  defp scan_with_pagination(bucket, prefix, continuation_token, file_processor, page_count \\ 1, processed_count \\ 0) do
    # Safety limit - don't scan more than 10 pages (10,000 objects per directory)
    max_pages = 10

    if page_count > max_pages do
      Logger.warning("Reached maximum page count (#{max_pages}) for #{prefix}. Stopping pagination.")
      processed_count
    else
      # Build options for list_objects_v2
      options = if is_nil(continuation_token) do
        [prefix: prefix, max_keys: @max_objects_per_page]
      else
        [prefix: prefix, max_keys: @max_objects_per_page, continuation_token: continuation_token]
      end

      # List objects in this directory
      case ExAws.S3.list_objects_v2(bucket, options) |> ExAws.request() do
        {:ok, %{body: %{contents: objects, is_truncated: is_truncated, next_continuation_token: next_token}}}
            when is_list(objects) and objects != [] ->

          Logger.info("Found #{length(objects)} objects in #{prefix} (page #{page_count})")

          # Track total objects scanned
          increment_stat(:total_objects_scanned, length(objects))

          # Process each object that passes the filter
          new_processed_count = Enum.reduce(objects, processed_count, fn %{key: key}, count ->
            local_path = get_local_path(key)
            result = file_processor.(key, local_path)

            if result do
              count + 1
            else
              count
            end
          end)

          # If the response was truncated and we have a valid next token, continue pagination
          # Only if the token is different from the current one to avoid loops
          if is_truncated && next_token && next_token != continuation_token do
            scan_with_pagination(bucket, prefix, next_token, file_processor, page_count + 1, new_processed_count)
          else
            Logger.info("Finished scanning #{prefix}, processed #{new_processed_count} files across #{page_count} pages")
            new_processed_count
          end

        {:ok, %{body: %{contents: []}}} ->
          Logger.info("No objects found in directory #{prefix}")
          processed_count

        {:error, error} ->
          Logger.error("Failed to list objects in #{prefix}: #{inspect(error)}")
          processed_count
      end
    end
  end

  # Process a file in dry run mode
  defp process_dry_run(key, local_path) do
    # Check if we've already processed this key
    case processed_key?(key) do
      true ->
        increment_stat(:duplicate_checks)
        false # Indicate the file was not actually processed
      false ->
        # Mark this key as processed
        add_processed_key(key)

        # Check if file exists locally
        if File.exists?(local_path) do
          increment_stat(:existing_files_count)
        else
          increment_stat(:missing_files_count)
          Logger.info("Would download: #{key} to #{local_path}")
        end
        true # Indicate the file was processed
    end
  end

  # Process a file and download if missing
  defp process_and_download(key, local_path, bucket) do
    # Check if we've already processed this key
    case processed_key?(key) do
      true ->
        increment_stat(:duplicate_checks)
        false # Indicate the file was not actually processed
      false ->
        # Mark this key as processed
        add_processed_key(key)

        # Check if file exists locally
        if File.exists?(local_path) do
          increment_stat(:existing_files_count)
        else
          # Create directory if needed
          File.mkdir_p!(Path.dirname(local_path))

          # Download the file
          case download_file(bucket, key, local_path) do
            :ok ->
              increment_stat(:download_count)
              Logger.info("Downloaded: #{key} to #{local_path}")
            :error ->
              increment_stat(:download_failures)
              Logger.error("Failed to download: #{key}")
          end
        end
        true # Indicate the file was processed
    end
  end

  # Download a file from S3
  defp download_file(bucket, key, local_path) do
    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        # Write file content
        File.write!(local_path, body)
        :ok

      {:error, error} ->
        Logger.error("Download error: #{inspect(error)}")
        :error
    end
  end

  # Get local file path corresponding to S3 key
  defp get_local_path(key) do
    # We want to preserve the exact folder structure, but skip the "uploads/" prefix
    # from the Tigris bucket if it exists
    if String.starts_with?(key, "uploads/") do
      # Remove the leading "uploads/" as we're already putting files in the uploads dir
      clean_key = String.replace_prefix(key, "uploads/", "")
      Path.join(@uploads_dir, clean_key)
    else
      # Just use the key as-is if it doesn't have the uploads prefix
      Path.join(@uploads_dir, key)
    end
  end

  # ETS-based utilities for tracking processed keys and stats

  # Check if a key has already been processed
  defp processed_key?(key) do
    [{:processed_keys, keys}] = :ets.lookup(:sync_image_stats, :processed_keys)
    MapSet.member?(keys, key)
  end

  # Add a key to the processed set
  defp add_processed_key(key) do
    [{:processed_keys, keys}] = :ets.lookup(:sync_image_stats, :processed_keys)
    updated_keys = MapSet.put(keys, key)
    :ets.insert(:sync_image_stats, {:processed_keys, updated_keys})
  end

  # Increment a stat counter
  defp increment_stat(stat, amount \\ 1) do
    [{^stat, value}] = :ets.lookup(:sync_image_stats, stat)
    :ets.insert(:sync_image_stats, {stat, value + amount})
  end

  # Display summary statistics
  defp display_stats do
    [{:missing_files_count, missing}] = :ets.lookup(:sync_image_stats, :missing_files_count)
    [{:existing_files_count, existing}] = :ets.lookup(:sync_image_stats, :existing_files_count)
    [{:download_count, downloaded}] = :ets.lookup(:sync_image_stats, :download_count)
    [{:duplicate_checks, duplicates}] = :ets.lookup(:sync_image_stats, :duplicate_checks)
    [{:download_failures, failures}] = :ets.lookup(:sync_image_stats, :download_failures)
    [{:processed_keys, keys}] = :ets.lookup(:sync_image_stats, :processed_keys)
    [{:total_objects_scanned, total_scanned}] = :ets.lookup(:sync_image_stats, :total_objects_scanned)

    unique_keys = MapSet.size(keys)

    Logger.info("""

    Image Sync Statistics:
    ----------------------
    Total objects scanned: #{total_scanned}
    Unique files processed: #{unique_keys}
    Existing files (skipped): #{existing}
    Missing files identified: #{missing}
    Files downloaded: #{downloaded}
    Download failures: #{failures}
    Duplicate file checks avoided: #{duplicates}
    """)
  end
end

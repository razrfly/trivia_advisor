defmodule TriviaAdvisor.Tasks.PerformerImageCleanup do
  @moduledoc """
  Module for cleaning up duplicate performer images.
  This is a production-friendly version that can be called from code.
  """
  require Logger

  @doc """
  Clean up duplicate performer image files by:
  1. Identifying performers with multiple image files
  2. Keeping only the most recent image file for each performer
  3. Deleting all other duplicate image files

  ## Options

    * `:dry_run` - Show what would be done without making changes (default: false)
    * `:base_dir` - Base directory where performer images are stored (default: "priv/static/uploads/performers")

  ## Returns

    * `{:ok, stats}` where stats is a map with cleanup statistics
  """
  def cleanup_duplicates(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    base_dir = Keyword.get(opts, :base_dir, "priv/static/uploads/performers")

    if dry_run do
      Logger.info("🔍 DRY RUN MODE - No changes will be made")
    end

    # Start the cleanup process
    stats = cleanup_duplicate_images(base_dir, dry_run)

    {:ok, stats}
  end

  @doc """
  Cleans up duplicate performer images on S3 storage.
  This is used for production environments that store images on S3.

  ## Options

    * `:dry_run` - Show what would be done without making changes (default: false)

  ## Returns

    * `{:ok, stats}` where stats is a map with cleanup statistics
    * `{:error, reason}` if the cleanup fails
  """
  def cleanup_s3_duplicates(opts \\ []) do
    if TriviaAdvisor.Uploaders.ProfileImage.__storage == Waffle.Storage.S3 do
      dry_run = Keyword.get(opts, :dry_run, false)
      Logger.info("🔍 Cleaning up S3 duplicate performer images")

      # Get S3 bucket from config
      s3_bucket = Application.get_env(:waffle, :bucket)
      s3_prefix = "uploads/performers/"

      unless s3_bucket do
        Logger.warning("⚠️ No S3 bucket configured")
        return_stats(%{error: "No S3 bucket configured"})
      end

      Logger.info("🔍 Listing objects in s3://#{s3_bucket}/#{s3_prefix}")

      # List all objects in the performers directory
      objects_result = ExAws.S3.list_objects(s3_bucket, prefix: s3_prefix)
        |> ExAws.request()

      case objects_result do
        {:ok, %{body: %{contents: objects}}} ->
          # Process S3 objects
          process_s3_objects(s3_bucket, objects, dry_run)

        {:error, error} ->
          Logger.error("⚠️ Error listing S3 objects: #{inspect(error)}")
          return_stats(%{error: "Failed to list S3 objects"})
      end
    else
      {:error, "Not using S3 storage"}
    end
  end

  # Process S3 objects, grouping by performer and cleaning up duplicates
  defp process_s3_objects(s3_bucket, objects, dry_run) do
    # Group objects by performer directories
    grouped_objects = objects
      |> Enum.map(fn %{key: key, last_modified: _last_modified} = obj ->
        # Extract performer directory from key
        # Format: "uploads/performers/performer_id/original_filename.jpg"
        case String.split(key, "/", trim: true) do
          ["uploads", "performers", performer_id | _rest] ->
            # Add performer_id to the object
            Map.put(obj, :performer_id, performer_id)
          _ ->
            # Skip objects that don't match the expected path format
            Map.put(obj, :performer_id, nil)
        end
      end)
      |> Enum.reject(fn obj -> is_nil(obj.performer_id) end)
      |> Enum.group_by(fn obj -> obj.performer_id end)

    dirs_count = map_size(grouped_objects)
    Logger.info("🔍 Found #{dirs_count} performer directories in S3")

    # Stats for tracking the cleanup
    results = Enum.reduce(grouped_objects, {0, 0}, fn {performer_id, objects}, {dirs_with_dupes, files_removed} ->
      # Group by type (original vs thumb)
      objects_by_type = Enum.group_by(objects, fn obj ->
        cond do
          String.contains?(obj.key, "/original_") -> :original
          String.contains?(obj.key, "/thumb_") -> :thumb
          true -> :other
        end
      end)

      original_objects = Map.get(objects_by_type, :original, [])
      thumb_objects = Map.get(objects_by_type, :thumb, [])

      orig_count = length(original_objects)
      thumb_count = length(thumb_objects)

      # Check if this directory has duplicates
      has_dupes = orig_count > 1 || thumb_count > 1

      if has_dupes do
        Logger.info("🖼️ Found duplicates for #{performer_id}: #{orig_count} original, #{thumb_count} thumb images")

        # Sort objects by last_modified (newest first)
        sort_by_date = fn objects ->
          Enum.sort_by(objects, fn obj -> obj.last_modified end, :desc)
        end

        # Keep only the newest original and thumb files
        {orig_to_keep, orig_to_delete} = case sort_by_date.(original_objects) do
          [] -> {[], []}
          [newest | rest] -> {[newest], rest}
        end

        {thumb_to_keep, thumb_to_delete} = case sort_by_date.(thumb_objects) do
          [] -> {[], []}
          [newest | rest] -> {[newest], rest}
        end

        # Log what we're keeping and deleting
        objects_to_delete = orig_to_delete ++ thumb_to_delete
        deleted_count = length(objects_to_delete)

        Logger.info("✅ Keeping: #{length(orig_to_keep)} original, #{length(thumb_to_keep)} thumb")
        Logger.info("🗑️ Deleting: #{length(orig_to_delete)} original, #{length(orig_to_delete)} thumb")

        # Delete duplicate files
        unless dry_run do
          Enum.each(objects_to_delete, fn obj ->
            Logger.debug("🗑️ Deleting: #{obj.key}")
            ExAws.S3.delete_object(s3_bucket, obj.key)
            |> ExAws.request()
            |> case do
              {:ok, _} -> :ok
              {:error, error} -> Logger.warning("⚠️ Failed to delete #{obj.key}: #{inspect(error)}")
            end
          end)
          Logger.info("✅ Successfully deleted #{deleted_count} duplicate files for #{performer_id}")
        end

        {dirs_with_dupes + 1, files_removed + deleted_count}
      else
        {dirs_with_dupes, files_removed}
      end
    end)

    {total_dirs_with_dupes, total_files_removed} = results

    Logger.info("📊 Summary: Found duplicates in #{total_dirs_with_dupes}/#{dirs_count} directories")
    if dry_run do
      Logger.info("📊 Would delete #{total_files_removed} duplicate files")
    else
      Logger.info("📊 Deleted #{total_files_removed} duplicate files")
    end

    Logger.info("✅ S3 cleanup completed successfully!")

    # Return stats
    stats = %{
      directories_checked: dirs_count,
      directories_with_duplicates: total_dirs_with_dupes,
      files_removed: total_files_removed,
      storage_type: :s3
    }

    {:ok, stats}
  end

  # Helper function to return stats with an error
  defp return_stats(error_info) do
    {:ok, %{
      directories_checked: 0,
      directories_with_duplicates: 0,
      files_removed: 0,
      storage_type: :s3
    } |> Map.merge(error_info)}
  end

  # Core cleanup logic for local file system
  defp cleanup_duplicate_images(performers_dir, dry_run) do
    # Check if the performers directory exists
    unless File.dir?(performers_dir) do
      Logger.info("📂 Performers directory not found at #{performers_dir}")
      # Return the stats directly instead of using 'return'
      %{
        directories_checked: 0,
        directories_with_duplicates: 0,
        files_removed: 0,
        storage_type: :local
      }
    else
      # Get all performer directories
      performer_dirs = File.ls!(performers_dir)
        |> Enum.map(fn dir -> Path.join(performers_dir, dir) end)
        |> Enum.filter(&File.dir?/1)

      dirs_count = length(performer_dirs)
      Logger.info("🔍 Found #{dirs_count} performer directories to check")

      # Process each performer directory
      {total_dirs_with_dupes, total_files_removed} = Enum.reduce(performer_dirs, {0, 0}, fn dir, {dirs_with_dupes, files_removed} ->
        basename = Path.basename(dir)

        # Get all image files in this directory
        files = File.ls!(dir)
          |> Enum.map(fn file -> Path.join(dir, file) end)
          |> Enum.filter(&File.regular?/1)

        # Group files by version (original or thumb)
        files_by_version = Enum.group_by(files, fn file ->
          cond do
            String.starts_with?(Path.basename(file), "original_") -> :original
            String.starts_with?(Path.basename(file), "thumb_") -> :thumb
            true -> :other
          end
        end)

        original_files = Map.get(files_by_version, :original, [])
        thumb_files = Map.get(files_by_version, :thumb, [])

        orig_count = length(original_files)
        thumb_count = length(thumb_files)

        # Check if this directory has duplicates
        has_dupes = orig_count > 1 || thumb_count > 1

        if has_dupes do
          Logger.info("🖼️ Found duplicates for #{basename}: #{orig_count} original, #{thumb_count} thumb images")

          # Sort files by modification time (newest first)
          sort_by_mtime = fn files ->
            Enum.sort_by(files, fn file ->
              case File.stat(file) do
                {:ok, %{mtime: mtime}} -> mtime
                _ -> {{0, 0, 0}, {0, 0, 0}}  # Default value for sorting if stat fails
              end
            end, :desc)  # Use simple :desc instead of {:desc, Date}
          end

          # Keep only the newest original and thumb files
          {orig_to_keep, orig_to_delete} = case sort_by_mtime.(original_files) do
            [] -> {[], []}
            [newest | rest] -> {[newest], rest}
          end

          {thumb_to_keep, thumb_to_delete} = case sort_by_mtime.(thumb_files) do
            [] -> {[], []}
            [newest | rest] -> {[newest], rest}
          end

          # Log what we're keeping and deleting
          files_to_delete = orig_to_delete ++ thumb_to_delete
          deleted_count = length(files_to_delete)

          Logger.info("✅ Keeping: #{length(orig_to_keep)} original, #{length(thumb_to_keep)} thumb")
          Logger.info("🗑️ Deleting: #{length(orig_to_delete)} original, #{length(thumb_to_delete)} thumb")

          # Delete duplicate files
          unless dry_run do
            Enum.each(files_to_delete, fn file ->
              Logger.debug("🗑️ Deleting: #{Path.basename(file)}")
              File.rm!(file)
            end)
            Logger.info("✅ Successfully deleted #{deleted_count} duplicate files")
          end

          {dirs_with_dupes + 1, files_removed + deleted_count}
        else
          {dirs_with_dupes, files_removed}
        end
      end)

      Logger.info("📊 Summary: Found duplicates in #{total_dirs_with_dupes}/#{dirs_count} directories")
      if dry_run do
        Logger.info("📊 Would delete #{total_files_removed} duplicate files")
      else
        Logger.info("📊 Deleted #{total_files_removed} duplicate files")
      end

      Logger.info("✅ Cleanup completed successfully!")

      %{
        directories_checked: dirs_count,
        directories_with_duplicates: total_dirs_with_dupes,
        files_removed: total_files_removed,
        storage_type: :local
      }
    end
  end
end

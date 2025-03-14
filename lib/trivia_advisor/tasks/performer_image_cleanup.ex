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
  def cleanup_s3_duplicates(_opts \\ []) do
    if TriviaAdvisor.Uploaders.ProfileImage.__storage == Waffle.Storage.S3 do
      Logger.info("🔍 Cleaning up S3 duplicate performer images")
      # Call the AWS S3 CLI to list all objects in the performers directory
      s3_bucket = Application.get_env(:waffle, :bucket)

      Logger.warning("⚠️ S3 cleanup not yet implemented")
      Logger.info("ℹ️ For S3 cleanup, you'll need to run AWS CLI commands manually:")
      Logger.info("ℹ️ aws s3 ls s3://#{s3_bucket}/uploads/performers/ --recursive > performer_images.txt")

      # Return empty stats for now
      {:ok, %{
        directories_checked: 0,
        directories_with_duplicates: 0,
        files_removed: 0,
        storage_type: :s3
      }}
    else
      {:error, "Not using S3 storage"}
    end
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
              Logger.debug("��️ Deleting: #{Path.basename(file)}")
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

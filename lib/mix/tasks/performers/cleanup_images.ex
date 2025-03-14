defmodule Mix.Tasks.Performers.CleanupImages do
  use Mix.Task
  require Logger

  @shortdoc "Clean up duplicate performer images, keeping only the most recent for each performer"

  @moduledoc """
  Cleans up duplicate performer image files by:
  1. Identifying performers with multiple image files
  2. Keeping only the most recent image file for each performer
  3. Deleting all other duplicate image files

  ## Usage

      mix performers.cleanup_images [options]

  ## Options

      --dry-run         Show what would be done without making changes

  ## Examples

      mix performers.cleanup_images
      mix performers.cleanup_images --dry-run
  """

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, switches: [
      dry_run: :boolean
    ])

    dry_run = Keyword.get(opts, :dry_run, false)

    if dry_run do
      Logger.info("🔍 DRY RUN MODE - No changes will be made")
    end

    # Start the application
    Mix.Task.run("app.start")

    # Start the cleanup process
    cleanup_duplicate_images(dry_run)
  end

  defp cleanup_duplicate_images(dry_run) do
    performers_dir = Path.join(["priv", "static", "uploads", "performers"])

    # Check if the performers directory exists
    unless File.dir?(performers_dir) do
      Logger.info("📂 Performers directory not found at #{performers_dir}")
      # Use return value instead of calling 'return'
      %{
        directories_checked: 0,
        directories_with_duplicates: 0,
        files_removed: 0,
        storage_type: :local
      }
      # Early exit
      exit({:shutdown, 0})
    end

    # Get all performer directories
    performer_dirs = File.ls!(performers_dir)
      |> Enum.map(fn dir -> Path.join(performers_dir, dir) end)
      |> Enum.filter(&File.dir?/1)

    Logger.info("🔍 Found #{length(performer_dirs)} performer directories to check")

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

    Logger.info("📊 Summary: Found duplicates in #{total_dirs_with_dupes} directories")
    if dry_run do
      Logger.info("📊 Would delete #{total_files_removed} duplicate files")
    else
      Logger.info("📊 Deleted #{total_files_removed} duplicate files")
    end

    Logger.info("✅ Cleanup completed successfully!")
  end
end

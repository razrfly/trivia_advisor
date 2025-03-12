defmodule Mix.Tasks.Performers.Reset do
  use Mix.Task
  require Logger
  import Ecto.Query

  @shortdoc "Removes performer IDs from Quizmeisters events and deletes all performers"

  @moduledoc """
  Resets performer data by:
  1. Setting performer_id to NULL for all Quizmeisters events
  2. Deleting all performers from the database
  3. Optionally deleting performer image directories

  ## Usage

      mix performers.reset [options]

  ## Options

      --keep-images     Don't delete performer image directories
      --dry-run         Show what would be done without making changes

  ## Examples

      mix performers.reset
      mix performers.reset --keep-images
      mix performers.reset --dry-run
  """

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, switches: [
      keep_images: :boolean,
      dry_run: :boolean
    ])

    dry_run = Keyword.get(opts, :dry_run, false)
    keep_images = Keyword.get(opts, :keep_images, false)

    if dry_run do
      Logger.info("🔍 DRY RUN MODE - No changes will be made")
    end

    # Start the application
    Mix.Task.run("app.start")

    # 1. Get Quizmeisters source
    source_id = get_quizmeisters_source_id()

    # 2. Set performer_id to NULL for all Quizmeisters events
    clear_performer_ids(source_id, dry_run)

    # 3. Delete all performers
    delete_performers(dry_run)

    # 4. Delete performer image directories (unless --keep-images is specified)
    unless keep_images do
      delete_performer_images(dry_run)
    end

    Logger.info("✅ Performer reset completed successfully!")
  end

  defp get_quizmeisters_source_id do
    case TriviaAdvisor.Repo.get_by(TriviaAdvisor.Scraping.Source, name: "quizmeisters") do
      nil ->
        Logger.error("❌ Quizmeisters source not found in the database")
        raise "Quizmeisters source not found"
      source ->
        Logger.info("📊 Found Quizmeisters source with ID: #{source.id}")
        source.id
    end
  end

  defp clear_performer_ids(source_id, dry_run) do
    # Find all events from the Quizmeisters source with non-nil performer_id
    query = from e in TriviaAdvisor.Events.Event,
            join: es in TriviaAdvisor.Events.EventSource,
            on: e.id == es.event_id,
            where: es.source_id == ^source_id and not is_nil(e.performer_id)

    # Count the affected events
    count = TriviaAdvisor.Repo.aggregate(query, :count, :id)
    Logger.info("🔄 Found #{count} Quizmeisters events with performer IDs")

    if count > 0 and not dry_run do
      # Update the events to set performer_id to nil
      {updated, _} = TriviaAdvisor.Repo.update_all(query, set: [performer_id: nil])
      Logger.info("✅ Removed performer IDs from #{updated} events")
    end
  end

  defp delete_performers(dry_run) do
    # Count the total number of performers
    count = TriviaAdvisor.Repo.aggregate(TriviaAdvisor.Events.Performer, :count, :id)
    Logger.info("🔄 Found #{count} performers to delete")

    if count > 0 and not dry_run do
      # Delete performers one by one to ensure before_delete callbacks are invoked
      performers = TriviaAdvisor.Repo.all(TriviaAdvisor.Events.Performer)

      deleted_count = Enum.reduce(performers, 0, fn performer, count ->
        case TriviaAdvisor.Repo.delete_with_callbacks(performer) do
          {:ok, _} -> count + 1
          {:error, error} ->
            Logger.error("❌ Error deleting performer #{performer.id}: #{inspect(error)}")
            count
        end
      end)

      Logger.info("✅ Successfully deleted #{deleted_count}/#{count} performers")
    end
  end

  defp delete_performer_images(dry_run) do
    # Path to the performers image directory
    performers_dir = Path.join(["priv", "static", "uploads", "performers"])

    # Check if the directory exists
    if File.dir?(performers_dir) do
      # Count subdirectories (performer image folders)
      {dirs, _files} = File.ls!(performers_dir)
                      |> Enum.map(fn entry -> Path.join(performers_dir, entry) end)
                      |> Enum.split_with(&File.dir?/1)

      dir_count = length(dirs)

      Logger.info("🔄 Found #{dir_count} performer image directories to delete")

      if dir_count > 0 and not dry_run do
        # Delete the entire performers directory and recreate it
        File.rm_rf!(performers_dir)
        File.mkdir_p!(performers_dir)

        Logger.info("✅ Successfully deleted and recreated the performers image directory")
      end
    else
      Logger.info("ℹ️ No performers image directory found at #{performers_dir}")

      # Create the directory if it doesn't exist and we're not in dry run mode
      if not dry_run do
        File.mkdir_p!(performers_dir)
        Logger.info("✅ Created performers image directory at #{performers_dir}")
      end
    end
  end
end

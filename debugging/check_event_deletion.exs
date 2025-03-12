alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.Event
alias TriviaAdvisor.Uploaders.HeroImage
import Ecto.Query

IO.puts("Testing event image deletion")
IO.puts("===========================")

# Find an event with an image
event = Repo.one(
  from e in Event,
  where: not is_nil(e.hero_image),
  order_by: [desc: e.id],
  limit: 1
)

if event do
  IO.puts("Found event: #{event.name} (ID: #{event.id})")

  # Get the file paths from the uploader
  file_name = event.hero_image.file_name

  if file_name do
    IO.puts("Hero image file name: #{file_name}")

    # Get all file paths that might be created by the uploader
    file_paths = HeroImage.urls({file_name, event})
    |> Enum.map(fn {_version, path} -> path end)

    IO.puts("Generated file paths:")
    Enum.each(file_paths, fn path -> IO.puts("  - #{path}") end)

    # Check which files actually exist
    existing_files = Enum.filter(file_paths, fn path ->
      # Convert to local file path
      local_path = Path.join("priv/static", URI.parse(path).path)
      exists = File.exists?(local_path)
      IO.puts("  - #{local_path}: #{if exists, do: "exists", else: "not found"}")
      exists
    end)

    if Enum.empty?(existing_files) do
      IO.puts("No files found to be deleted. Skipping deletion test.")
    else
      # Delete the event and check if files were removed
      IO.puts("\nDeleting event #{event.id}...")

      # Use delete_with_callbacks
      case Repo.delete_with_callbacks(event) do
        {:ok, _deleted} ->
          IO.puts("Event deleted successfully")

          # Check if files were removed
          IO.puts("\nChecking if files were removed:")

          deleted_files = Enum.filter(existing_files, fn path ->
            local_path = Path.join("priv/static", URI.parse(path).path)
            not File.exists?(local_path)
          end)

          if length(deleted_files) == length(existing_files) do
            IO.puts("✅ All files were successfully deleted!")
          else
            IO.puts("❌ Some files were not deleted:")
            remaining_files = existing_files -- deleted_files

            Enum.each(remaining_files, fn path ->
              local_path = Path.join("priv/static", URI.parse(path).path)
              IO.puts("  - #{local_path}")
            end)
          end

        {:error, changeset} ->
          IO.puts("Failed to delete event: #{inspect(changeset.errors)}")
      end
    end
  else
    IO.puts("Event has no hero image file name. Skipping deletion test.")
  end
else
  IO.puts("No events with hero images found.")
end

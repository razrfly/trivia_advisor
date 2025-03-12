alias TriviaAdvisor.Repo
alias TriviaAdvisor.Events.{Performer, Event}
alias TriviaAdvisor.Uploaders.ProfileImage
import Ecto.Query

IO.puts("Testing performer image deletion")
IO.puts("===============================")

# Find a performer with an image
performer = Repo.one(
  from p in Performer,
  where: not is_nil(p.profile_image) and p.source_id == 4,
  order_by: [desc: p.id],
  limit: 1
)

if performer do
  IO.puts("Found performer: #{performer.name} (ID: #{performer.id})")

  # Check if performer is associated with any events
  events = Repo.all(
    from e in Event,
    where: e.performer_id == ^performer.id
  )

  if events && length(events) > 0 do
    IO.puts("Performer is associated with #{length(events)} events. Removing associations first...")

    # Remove associations by setting performer_id to nil
    Enum.each(events, fn event ->
      IO.puts("  - Removing performer from event: #{event.id}")

      event
      |> Ecto.Changeset.change(%{performer_id: nil})
      |> Repo.update!()
    end)

    IO.puts("All event associations removed")
  else
    IO.puts("Performer is not associated with any events")
  end

  # Get the file paths from the uploader
  file_name = performer.profile_image.file_name

  if file_name do
    IO.puts("Profile image file name: #{file_name}")

    # Get all file paths that might be created by the uploader
    file_paths = ProfileImage.urls({file_name, performer})
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
      # Delete the performer and check if files were removed
      IO.puts("\nDeleting performer #{performer.id}...")

      # Use delete_with_callbacks instead of delete
      case Repo.delete_with_callbacks(performer) do
        {:ok, _deleted} ->
          IO.puts("Performer deleted successfully")

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
          IO.puts("Failed to delete performer: #{inspect(changeset.errors)}")
      end
    end
  else
    IO.puts("Performer has no profile image file name. Skipping deletion test.")
  end
else
  IO.puts("No performers with profile images found.")
end

defmodule TriviaAdvisor.Events.Performer do
  use Ecto.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Scraping.Source
  use Waffle.Ecto.Schema

  schema "performers" do
    field :name, :string
    field :profile_image, TriviaAdvisor.Uploaders.ProfileImage.Type

    belongs_to :source, Source

    timestamps()
  end

  @doc false
  def changeset(performer, attrs) do
    performer
    |> cast(attrs, [:name, :source_id])
    |> maybe_cast_profile_image(attrs)
    |> validate_required([:name, :source_id])
    |> foreign_key_constraint(:source_id)
  end

  defp maybe_cast_profile_image(changeset, attrs) do
    require Logger

    # Log what we received in attrs
    Logger.debug("📸 Profile image attribute: #{inspect(attrs[:profile_image])}")

    cond do
      # If we have the downloaded file with _temp_path, copy it to the appropriate location
      # This is the format from our modified ImageDownloader.download_performer_image
      is_map(attrs[:profile_image]) and Map.has_key?(attrs[:profile_image], :file_name) and Map.has_key?(attrs[:profile_image], :_temp_path) ->
        Logger.debug("📁 Handling file with temp path: #{inspect(attrs[:profile_image])}")

        # First, store the file metadata in the changeset
        changeset = cast(changeset, %{profile_image: %{
          file_name: attrs[:profile_image].file_name,
          updated_at: attrs[:profile_image].updated_at
        }}, [:profile_image])

        # Manually copy the file to the expected location
        # Use Elixir Task to do this asynchronously
        Task.start(fn ->
          try do
            # Get the performer ID - either from the changeset if it's an update or from the inserted record if it's new
            performer_id = case Ecto.Changeset.get_field(changeset, :id) do
              nil ->
                # New record - need to wait for insert
                Process.sleep(500)  # Give time for the DB insert to complete
                # Try to get the inserted performer by name and source_id
                performer = TriviaAdvisor.Repo.get_by(__MODULE__,
                  name: Ecto.Changeset.get_field(changeset, :name),
                  source_id: Ecto.Changeset.get_field(changeset, :source_id))
                performer && performer.id
              id -> id  # Existing record
            end

            if performer_id do
              # Format the performer name for the directory
              performer_name = Ecto.Changeset.get_field(changeset, :name)
                |> String.downcase()
                |> String.replace(~r/[^a-z0-9]+/, "-")
                |> String.trim("-")

              # Create the directory structure
              dir = Path.join(["priv", "static", "uploads", "performer_profile_images", "#{performer_name}-#{performer_id}"])
              File.mkdir_p!(dir)

              # Copy the file for both original and thumbnail versions
              original_file = Path.join(dir, "original_#{attrs[:profile_image].file_name}")
              thumb_file = Path.join(dir, "thumb_#{attrs[:profile_image].file_name}")

              File.cp!(attrs[:profile_image]._temp_path, original_file)
              File.cp!(attrs[:profile_image]._temp_path, thumb_file)

              Logger.debug("✅ Successfully copied files to #{dir}")
            else
              Logger.error("❌ Could not determine performer ID for file storage")
            end
          rescue
            e -> Logger.error("❌ Error copying files: #{inspect(e)}")
          end
        end)

        changeset

      # If we have a file struct with both filename and path, use cast_attachments (old format)
      is_map(attrs[:profile_image]) and Map.has_key?(attrs[:profile_image], :filename) and Map.has_key?(attrs[:profile_image], :path) ->
        Logger.debug("💾 Using cast_attachments for profile image: #{inspect(attrs[:profile_image])}")
        cast_attachments(changeset, attrs, [:profile_image])

      # If we just have a path map (older format), convert it to the expected format
      is_map(attrs[:profile_image]) and Map.has_key?(attrs[:profile_image], :path) and not Map.has_key?(attrs[:profile_image], :filename) and not Map.has_key?(attrs[:profile_image], :file_name) ->
        path = attrs[:profile_image].path
        filename = Path.basename(path)

        Logger.debug("🔄 Converting path-only map to file_name+updated_at for profile image: #{path} -> #{filename}")

        # Create a new map with the correct keys for Waffle
        new_attrs = Map.put(attrs, :profile_image, %{file_name: filename, _temp_path: path, updated_at: NaiveDateTime.utc_now()})

        # Handle the file with our custom logic
        maybe_cast_profile_image(changeset, new_attrs)

      # If we have a file name and updated_at (saved record format), use Waffle cast
      is_map(attrs[:profile_image]) and Map.has_key?(attrs[:profile_image], :file_name) and Map.has_key?(attrs[:profile_image], :updated_at) ->
        Logger.debug("📝 Using file_name and updated_at for profile image: #{inspect(attrs[:profile_image])}")
        cast(changeset, %{profile_image: attrs[:profile_image]}, [:profile_image])

      # If we have a string (filename from Waffle), use cast
      is_binary(attrs[:profile_image]) ->
        Logger.debug("🏷️ Using string filename for profile image: #{attrs[:profile_image]}")
        cast(changeset, %{profile_image: %{file_name: attrs[:profile_image], updated_at: DateTime.utc_now()}}, [:profile_image])

      # Profile image is nil or invalid, don't change anything
      true ->
        Logger.debug("⏭️ No valid profile image data, skipping")
        changeset
    end
  end

  @doc """
  Finds or creates a performer by name and source_id.
  Updates the profile image if it has changed.
  """
  def find_or_create(attrs = %{name: name, source_id: source_id}) do
    case TriviaAdvisor.Repo.get_by(__MODULE__, name: name, source_id: source_id) do
      nil -> %__MODULE__{}
      performer -> performer
    end
    |> changeset(attrs)
    |> TriviaAdvisor.Repo.insert_or_update()
  end
end

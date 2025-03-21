defmodule TriviaAdvisor.Events.Performer do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias TriviaAdvisor.Scraping.Source
  use Waffle.Ecto.Schema
  require Logger

  schema "performers" do
    field :name, :string
    field :profile_image, TriviaAdvisor.Uploaders.ProfileImage.Type

    belongs_to :source, Source

    timestamps()
  end

  # Add before_delete callback to delete files when the record is deleted
  def before_delete(%{profile_image: profile_image} = performer) do
    if profile_image && profile_image.file_name do
      Logger.info("🗑️ Deleting profile image files for performer: #{performer.name}")

      # Construct the storage directory path
      performer_name = performer.name
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "-")
        |> String.trim("-")

      dir = Path.join(["priv", "static", "uploads", "performers", "#{performer_name}-#{performer.id}"])

      if File.exists?(dir) do
        # Manually delete the directory and all its contents
        case File.rm_rf(dir) do
          {:ok, _} ->
            Logger.info("✅ Successfully deleted profile image files for performer: #{performer.name}")
          {:error, reason, _} ->
            Logger.error("❌ Error deleting profile images: #{inspect(reason)}")
        end
      else
        Logger.info("⚠️ No profile image directory found at #{dir}")
      end
    end
  end
  # Catch-all for performers without images
  def before_delete(_), do: :ok

  @doc false
  def changeset(performer, attrs) do
    performer
    |> cast(attrs, [:name, :source_id])
    |> cast_attachments(attrs, [:profile_image])
    |> validate_required([:name, :source_id])
    |> foreign_key_constraint(:source_id)
  end

  @doc """
  Finds or creates a performer by name and source_id.
  Updates the profile image if it has changed.
  """
  def find_or_create(attrs = %{name: name, source_id: source_id}) when not is_nil(name) do
    # Handle potential duplicates by using Repo.all and taking the first result
    case TriviaAdvisor.Repo.all(from p in __MODULE__, where: p.name == ^name and p.source_id == ^source_id) do
      [] ->
        # No performer found, create a new one
        Logger.info("🎭 Creating new performer '#{name}' with image: #{if Map.has_key?(attrs, :profile_image), do: "yes", else: "no"}")
        %__MODULE__{}
        |> changeset(attrs)
        |> TriviaAdvisor.Repo.insert()

      [performer | _rest] = performers ->
        # Log if we found multiple performers
        if length(performers) > 1 do
          Logger.warning("⚠️ Found #{length(performers)} duplicate performers for '#{name}' (source_id: #{source_id}). Using the first one.")
        end

        # Check if the performer's image needs to be updated
        if Map.has_key?(attrs, :profile_image) do
          # If the new attrs contain an image, get the filename
          case attrs.profile_image do
            %Plug.Upload{filename: new_filename} ->
              # Get current filename
              current_filename = if performer.profile_image, do: get_in(performer.profile_image, [:file_name]), else: nil

              # Check if the filename has changed
              if current_filename != new_filename do
                Logger.info("🔄 Updating performer '#{name}' image from '#{current_filename}' to '#{new_filename}'")
                performer
                |> changeset(attrs)
                |> TriviaAdvisor.Repo.update()
              else
                Logger.info("✅ Performer '#{name}' image is unchanged (#{current_filename})")
                {:ok, performer}
              end

            _ ->
              # No valid image in attrs, keep the performer as is
              Logger.info("✅ No new valid image for performer '#{name}', keeping existing data")
              {:ok, performer}
          end
        else
          # No image in attrs, keep the performer as is
          Logger.info("✅ Performer '#{name}' exists and no new image provided")
          {:ok, performer}
        end
    end
  end

  # Handle case where name is nil
  def find_or_create(%{source_id: source_id} = _attrs) do
    Logger.warning("❌ Attempted to create performer with nil name for source_id: #{source_id}")
    {:error, "Performer name cannot be nil"}
  end
end

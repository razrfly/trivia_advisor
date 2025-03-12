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
        %__MODULE__{}
      [performer] ->
        # Only one performer found, use it
        performer
      performers when is_list(performers) ->
        # Multiple performers found, log the issue and use the first one
        Logger.warning("⚠️ Found #{length(performers)} duplicate performers for '#{name}' (source_id: #{source_id}). Using the first one.")
        List.first(performers)
    end
    |> changeset(attrs)
    |> TriviaAdvisor.Repo.insert_or_update()
  end

  # Handle case where name is nil
  def find_or_create(%{source_id: source_id} = _attrs) do
    Logger.warning("❌ Attempted to create performer with nil name for source_id: #{source_id}")
    {:error, "Performer name cannot be nil"}
  end
end

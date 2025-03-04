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
    cond do
      # If we have a file struct, use cast_attachments
      is_map(attrs[:profile_image]) and Map.has_key?(attrs[:profile_image], :filename) ->
        cast_attachments(changeset, attrs, [:profile_image])

      # If we have a string (filename from Waffle), use cast
      is_binary(attrs[:profile_image]) ->
        cast(changeset, %{profile_image: %{file_name: attrs[:profile_image], updated_at: DateTime.utc_now()}}, [:profile_image])

      # Otherwise, don't change anything
      true ->
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

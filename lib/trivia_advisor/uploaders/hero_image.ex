defmodule TriviaAdvisor.Uploaders.HeroImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  # Define a thumbnail transformation
  @versions [:original, :thumb]

  @acl :public_read

  # Whitelist file extensions
  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    ~w(.jpg .jpeg .gif .png .webp .avif) |> Enum.member?(file_extension)
  end

  # Define a thumbnail transformation:
  def transform(:thumb, {_file, _}) do
    {:convert, "-strip -thumbnail 250x250^ -gravity center -extent 250x250 -format jpg"}
  end

  # Override the storage directory to use venue slug
  def storage_dir(_version, {_file, scope}) do
    venue = case scope.venue do
      %Ecto.Association.NotLoaded{} ->
        # Reload venue if not loaded
        TriviaAdvisor.Repo.preload(scope, :venue).venue
      loaded -> loaded
    end
    "priv/static/uploads/venues/#{venue.slug}"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    "/images/default-hero.jpg"
  end

  # Generate a unique filename, converting webp/avif to jpg for thumbnails
  def filename(version, {file, _scope}) do
    name = Path.basename(file.file_name, Path.extname(file.file_name))
   #ext = Path.extname(file.file_name)

    case version do
      :thumb -> "#{name}_#{version}"
      _ -> "#{name}_#{version}"     # Keep original extension
    end
  end
end

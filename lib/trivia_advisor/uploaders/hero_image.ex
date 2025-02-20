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
  def transform(:thumb, {file, _}) do
    ext = file.file_name |> Path.extname() |> String.downcase()
    case ext do
      e when e in [".webp", ".avif"] ->
        {:convert, "-strip -thumbnail 250x250^ -gravity center -extent 250x250 -format jpg"}
      _ ->
        {:convert, "-strip -thumbnail 250x250^ -gravity center -extent 250x250"}
    end
  end

  # Override the storage directory:
  def storage_dir(_version, {_file, scope}) do
    "priv/static/uploads/events/#{scope.id}"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    "/images/default-hero.jpg"
  end

  # Generate a unique filename, converting webp/avif to jpg for thumbnails
  def filename(version, {file, _scope}) do
    name = Path.basename(file.file_name, Path.extname(file.file_name))
    ext = Path.extname(file.file_name)

    case version do
      :thumb -> "#{name}_#{version}.jpg"  # Always use jpg for thumbnails
      _ -> "#{name}_#{version}#{ext}"     # Keep original extension
    end
  end
end

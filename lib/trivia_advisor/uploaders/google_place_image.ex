defmodule TriviaAdvisor.Uploaders.GooglePlaceImage do
  use Waffle.Definition

  # Define original and thumbnail versions
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
    venue_id = scope[:venue_id]
    venue_slug = scope[:venue_slug]
    "priv/static/uploads/google_place_images/#{venue_slug || venue_id}"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    "/images/default-venue.jpg"
  end

  # Generate a unique filename
  def filename(version, {file, scope}) do
    position = scope[:position] || 1
    name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{name}_#{version}_#{position}"
  end
end

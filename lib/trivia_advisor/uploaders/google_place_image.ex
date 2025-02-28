defmodule TriviaAdvisor.Uploaders.GooglePlaceImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  # Define original and thumbnail versions
  @versions [:original, :thumb]

  @acl :public_read

  # Whitelist file extensions
  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    Enum.member?(~w(.jpg .jpeg .gif .png .webp .avif), file_extension)
  end

  # Define a thumbnail transformation:
  def transform(:thumb, _) do
    {:convert, "-thumbnail 300x300^ -gravity center -extent 300x300"}
  end

  # Override the storage directory to use venue slug
  def storage_dir(_version, {_file, {venue_id, venue_slug, _position}}) do
    "uploads/google_place_images/#{venue_slug || venue_id}"
  end

  # Handle map format
  def storage_dir(_version, {_file, %{venue_id: venue_id, venue_slug: venue_slug}}) do
    "uploads/google_place_images/#{venue_slug || venue_id}"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    "https://placehold.co/600x400/png"
  end

  # Generate a unique filename - tuple format
  def filename(version, {file, {_venue_id, _venue_slug, position}}) do
    file_name = Path.rootname(file.file_name)
    file_extension = Path.extname(file.file_name)
    "#{version}_#{file_name}_#{position}#{file_extension}"
  end

  # Generate a unique filename - map format
  def filename(version, {file, %{position: position}}) do
    file_name = Path.rootname(file.file_name)
    file_extension = Path.extname(file.file_name)
    "#{version}_#{file_name}_#{position}#{file_extension}"
  end
end

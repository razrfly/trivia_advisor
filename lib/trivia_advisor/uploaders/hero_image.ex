defmodule TriviaAdvisor.Uploaders.HeroImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  # Define a thumbnail transformation
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

  # Temporary storage_dir when venue not loaded
  def storage_dir(_version, {_file, scope}) when is_nil(scope), do: "uploads/venues/temp"

  # Final storage_dir after venue loaded
  def storage_dir(_version, {_file, scope}) do
    scope = TriviaAdvisor.Venues.maybe_preload_venue(scope)

    if not is_nil(scope.venue) do
      venue = scope.venue
      "uploads/venues/#{venue.slug}"
    else
      "uploads/venues/temp"
    end
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    "https://placehold.co/600x400/png"
  end

  # Generate a unique filename, without adding extension (Waffle adds it automatically)
  def filename(version, {file, _scope}) do
    # Extract the base filename without extension
    file_name = Path.rootname(file.file_name)
    # Sanitize the filename to ensure it's URL-safe
    file_name = String.replace(file_name, ~r/[^a-zA-Z0-9\-_]/, "-")
    # Return just the version prefix and sanitized name (Waffle adds extension)
    "#{version}_#{file_name}"
  end

  # Override the URL generation to use our S3Helpers for consistent handling
  def url(definition, version, options) do
    base_url = super(definition, version, options)

    if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
      # Let S3Helpers handle this URL via construct_url in other parts of the code
      base_url
    else
      # In local development, apply the normal Waffle URL handling
      base_url
    end
  end
end

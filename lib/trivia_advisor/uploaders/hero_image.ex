defmodule TriviaAdvisor.Uploaders.HeroImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  require Logger

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
    # Get complete filename and strip any query string
    original_name = file.file_name
      |> String.split("?") |> List.first() # Remove query parameters

    # Check if we have a file extension, remove it because Waffle will add it automatically
    base_name = Path.rootname(original_name)

    # Only do minimal sanitization for truly problematic characters
    # but preserve most of the original name structure
    sanitized_name = String.replace(base_name, ~r/[<>:"|?*\0]/, "-")

    # Skip adding the version prefix for original versions to keep filename clean
    # Only add version for thumbnails
    case version do
      :original -> sanitized_name
      _ -> "#{version}_#{sanitized_name}"
    end
  end

  # Override default delete implementation to ensure files are actually deleted
  # from the filesystem with proper path resolution
  def delete({file_name, scope}) do
    # Ensure scope has venue loaded for slug
    scope = TriviaAdvisor.Venues.maybe_preload_venue(scope)

    venue_slug = if not is_nil(scope.venue), do: scope.venue.slug, else: "temp"

    # Construct base path
    priv_dir = Application.app_dir(:trivia_advisor, "priv/static")
    base_path = Path.join([priv_dir, "uploads", "venues", venue_slug])

    # All file versions that might exist
    file_paths = @versions
      |> Enum.map(fn version ->
        version_prefix = if version == :original, do: "", else: "#{version}_"
        Path.join(base_path, "#{version_prefix}#{file_name}")
      end)

    # Delete all files - log success or failure
    deleted_count = Enum.reduce(file_paths, 0, fn path, count ->
      if File.exists?(path) do
        Logger.info("🗑️ Physically deleting hero image at: #{path}")
        case File.rm(path) do
          :ok ->
            Logger.info("✅ Successfully deleted hero image: #{path}")
            count + 1
          {:error, reason} ->
            Logger.error("❌ Failed to delete hero image at #{path}: #{inspect(reason)}")
            count
        end
      else
        Logger.info("⚠️ Hero image file not found at: #{path}")
        count
      end
    end)

    # Return true if at least one file was deleted
    deleted_count > 0
  end
end

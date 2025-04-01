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

  # Define S3 bucket (required for S3 storage)
  def bucket(_), do: Application.get_env(:waffle, :bucket)

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

  # Override Waffle's delete to handle both legacy and new filename patterns
  defoverridable [delete: 1]

  def delete(args) do
    # Use built-in Waffle delete functionality for current pattern
    # This works for both local files and S3 automatically based on environment
    result = super(args)

    # Now also handle deleting legacy "original_" files
    try do
      # Extract filename for legacy handling
      {file_name, scope} = case args do
        {name, scp} when is_binary(name) -> {name, scp}
        name when is_binary(name) -> {name, nil}
        _ -> {nil, nil}
      end

      # Only handle original versions (thumbnails always had a prefix)
      if file_name do
        # Log our attempt to clean up legacy files
        Logger.info("🔍 LEGACY CLEANUP: Looking for old naming pattern with 'original_' prefix for #{file_name}")

        # Create a mock file with the legacy filename pattern
        legacy_file = %{file_name: "original_#{file_name}"}

        # Call original Waffle delete with the legacy file
        # This will use Waffle's built-in storage mechanisms to delete in both local and S3
        Logger.info("🧹 LEGACY CLEANUP: Attempting to delete 'original_#{file_name}'")
        super({legacy_file, scope})
        Logger.info("✅ LEGACY CLEANUP: Successfully processed legacy deletion")
      end
    rescue
      e ->
        # Log but don't fail if legacy cleanup fails
        Logger.error("⚠️ LEGACY CLEANUP: Error cleaning legacy files: #{inspect(e)}")
    end

    # Return the result of the original delete
    result
  end

  # Generate backward-compatible URLs for existing files
  def backwards_compatible_url(version, {file_name, scope}) do
    if is_binary(file_name) do
      try do
        # Try with the new format first
        new_format_url = url(version, {%{file_name: file_name}, scope})

        # If that fails, try with the legacy format
        if version == :original do
          # For original version, also try with "original_" prefix
          legacy_file_name = "original_#{file_name}"
          url(version, {%{file_name: legacy_file_name}, scope})
        else
          # For other versions, just return the standard URL
          new_format_url
        end
      rescue
        # If URL generation fails, return a default URL
        _ -> default_url(version, scope)
      end
    else
      # If file_name is not a string, return default URL
      default_url(version, scope)
    end
  end
end

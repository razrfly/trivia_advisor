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

  # Generate a unique filename, with prefix for all versions
  def filename(version, {file, _scope}) do
    # Get complete filename and strip any query string
    original_name = file.file_name
      |> String.split("?") |> List.first() # Remove query parameters

    # Check if we have a file extension, remove it because Waffle will add it automatically
    base_name = Path.rootname(original_name)

    # Only do minimal sanitization for truly problematic characters
    # but preserve most of the original name structure
    sanitized_name = String.replace(base_name, ~r/[<>:"|?*\0]/, "-")

    # CHANGED: Always add prefix for all versions, including original
    # This maintains compatibility with existing images
    case version do
      :original -> "original_#{sanitized_name}"
      _ -> "#{version}_#{sanitized_name}"
    end
  end

  # This function gets called by Waffle immediately before deleting files
  # It's the perfect place to add our directory wiping logic
  def before_delete({file_name, scope}) do
    # Ensure scope has venue loaded for slug
    scope = TriviaAdvisor.Venues.maybe_preload_venue(scope)

    venue_slug = if not is_nil(scope.venue), do: scope.venue.slug, else: "temp"

    # Get force_refresh_images from process dictionary
    force_refresh_images = Process.get(:force_refresh_images, false)

    # Log the deletion attempt with force_refresh_images status
    Logger.info("🗑️ Before deleting hero image: #{file_name} (force_refresh=#{force_refresh_images})")

    # If force_refresh_images is true, delete all files in the directory
    if force_refresh_images do
      Logger.warning("⚠️ TEMPORARY FIX: Wiping all files in venue image directory for venue slug: #{venue_slug}")
      temporary_delete_all_files_in_directory(venue_slug)
    end

    # Always return :ok to continue with the deletion
    :ok
  end

  # TEMPORARY FUNCTION: Deletes all files in the venue image directory on S3
  # This is a temporary solution to clean up old/dangling files
  defp temporary_delete_all_files_in_directory(venue_slug) do
    # Only do this in production where S3 is used
    if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
      bucket = Application.get_env(:waffle, :bucket)
      prefix = "uploads/venues/#{venue_slug}/"

      Logger.warning("🧨 TEMPORARY FIX: Wiping S3 directory: #{bucket}/#{prefix}")

      try do
        # List all objects with the prefix
        case ExAws.S3.list_objects(bucket, prefix: prefix)
             |> ExAws.request() do
          {:ok, %{body: %{contents: objects}}} ->
            if objects == [] or is_nil(objects) do
              Logger.info("ℹ️ No objects found in S3 directory: #{bucket}/#{prefix}")
              false
            else
              # Extract keys from objects
              keys = Enum.map(objects, fn %{key: key} -> key end)

              Logger.warning("🔥 TEMPORARY FIX: Found #{length(keys)} objects to delete")

              # Delete all objects in one request (S3 allows up to 1000 keys per delete request)
              delete_result = ExAws.S3.delete_multiple_objects(bucket, keys)
                             |> ExAws.request()

              case delete_result do
                {:ok, result} ->
                  deleted_count = result.body.deleted |> length()
                  Logger.info("✅ TEMPORARY FIX: Successfully deleted #{deleted_count} objects from S3")
                  true
                {:error, error} ->
                  Logger.error("❌ TEMPORARY FIX: Failed to delete objects from S3: #{inspect(error)}")
                  false
              end
            end
          {:error, error} ->
            Logger.error("❌ TEMPORARY FIX: Failed to list objects in S3: #{inspect(error)}")
            false
        end
      rescue
        e ->
          Logger.error("💥 TEMPORARY FIX: Exception in S3 directory wipe: #{inspect(e)}")
          Logger.error("💥 TEMPORARY FIX: Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
          false
      end
    else
      Logger.info("ℹ️ Skipping S3 directory wipe in non-production environment")
      false
    end
  end
end

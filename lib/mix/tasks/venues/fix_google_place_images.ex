defmodule Mix.Tasks.Venues.FixGooglePlaceImages do
  use Mix.Task
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue

  @shortdoc "Fix venues with Google Place images missing local paths"

  @moduledoc """
  This task finds venues with Google Place images that don't have local_path set,
  and adds expected local paths directly to the database.

  ## Examples

      mix venues.fix_google_place_images           # Processes up to 100 venues by default
      mix venues.fix_google_place_images --limit=10 # Processes up to 10 venues
      mix venues.fix_google_place_images --all     # Processes ALL venues in the database
  """

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, strict: [limit: :integer, all: :boolean])
    process_all = Keyword.get(opts, :all, false)
    limit = if process_all, do: nil, else: Keyword.get(opts, :limit, 100)

    # Start applications
    [:postgrex, :ecto, :trivia_advisor]
    |> Enum.each(&Application.ensure_all_started/1)

    # Find venues with Google Place images missing local paths
    venues_to_fix = find_venues_with_missing_local_paths(limit)

    venue_count = length(venues_to_fix)
    limit_msg = if process_all, do: "ALL", else: limit
    Logger.info("Found #{venue_count} venues with Google Place images missing local paths (limit: #{limit_msg})")

    # Process each venue
    Enum.each(venues_to_fix, fn venue ->
      Logger.info("Processing venue #{venue.id}: #{venue.name}")

      case update_venue_with_local_paths(venue) do
        {:ok, updated_venue} ->
          image_count = length(updated_venue.google_place_images || [])
          Logger.info("✅ Successfully updated venue #{venue.id} with #{image_count} images")
        {:error, reason} ->
          Logger.error("❌ Failed to update venue #{venue.id}: #{inspect(reason)}")
      end
    end)

    Logger.info("Finished fixing Google Place images for #{venue_count} venues")
  end

  # Find venues with Google Place images missing local paths
  defp find_venues_with_missing_local_paths(nil) do
    # No limit - get all venues
    venues = Repo.all(Venue)

    # Filter for venues with images missing local paths
    venues
    |> Enum.filter(fn venue ->
      has_images_missing_local_path?(venue.google_place_images)
    end)
  end

  defp find_venues_with_missing_local_paths(limit) when is_integer(limit) do
    # Find venues with Google Place images
    venues = Repo.all(Venue)

    # Filter for venues with images missing local paths
    venues
    |> Enum.filter(fn venue ->
      has_images_missing_local_path?(venue.google_place_images)
    end)
    |> Enum.take(limit)
  end

  # Check if any image in the list is missing a local_path
  defp has_images_missing_local_path?(nil), do: false
  defp has_images_missing_local_path?([]), do: false
  defp has_images_missing_local_path?(images) when is_list(images) do
    Enum.any?(images, fn image ->
      is_map(image) &&
      (is_nil(image["local_path"]) || image["local_path"] == "")
    end)
  end

  # Update venue with expected local paths without checking if files exist
  defp update_venue_with_local_paths(venue) do
    Logger.info("🔄 Adding local paths for venue #{venue.id} (#{venue.name})")

    # Check if any images need fixing
    images_to_fix = venue.google_place_images || []
    if Enum.empty?(images_to_fix) do
      Logger.info("⚠️ No images to fix for venue #{venue.id}")
      {:error, :no_images}
    else
      # Map each image to include expected local path
      fixed_images = Enum.map(images_to_fix, fn image ->
        if is_nil(image["local_path"]) || image["local_path"] == "" do
          # Construct expected path based on position
          position = image["position"]
          expected_path = "/uploads/google_place_images/#{venue.slug}/original_google_place_#{position}.jpg"

          # Add local_path without checking if file exists
          Logger.info("📝 Adding path for venue #{venue.id}, position #{position}: #{expected_path}")
          Map.put(image, "local_path", expected_path)
        else
          # Image already has local_path
          image
        end
      end)

      # Count how many were fixed
      fixed_count = Enum.count(fixed_images, fn image ->
        not is_nil(image["local_path"]) && image["local_path"] != ""
      end)
      total_count = length(fixed_images)

      # Update venue with fixed image data
      result = venue
        |> Venue.changeset(%{google_place_images: fixed_images})
        |> Repo.update()

      case result do
        {:ok, updated_venue} ->
          Logger.info("📊 Updated #{fixed_count}/#{total_count} images for venue #{venue.id}")
          {:ok, updated_venue}
        error ->
          error
      end
    end
  end
end

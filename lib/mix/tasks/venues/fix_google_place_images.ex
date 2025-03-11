defmodule Mix.Tasks.Venues.FixGooglePlaceImages do
  use Mix.Task
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @shortdoc "Fix venues with Google Place images missing local paths"

  @moduledoc """
  This task finds venues with Google Place images that don't have local_path set,
  and fixes them by downloading the images and updating the venue records with local paths.

  ## Examples

      mix venues.fix_google_place_images
      mix venues.fix_google_place_images --limit=10
  """

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, strict: [limit: :integer])
    limit = Keyword.get(opts, :limit, 100)

    # Start applications
    [:postgrex, :ecto, :trivia_advisor]
    |> Enum.each(&Application.ensure_all_started/1)

    # Find venues with Google Place images missing local paths
    venues_to_fix = find_venues_with_missing_local_paths(limit)

    Logger.info("Found #{length(venues_to_fix)} venues with Google Place images missing local paths")

    # Process each venue
    Enum.each(venues_to_fix, fn venue ->
      Logger.info("Processing venue #{venue.id}: #{venue.name}")

      # Fix the venue's Google Place images
      case GooglePlaceImageStore.process_venue_images(venue) do
        {:ok, updated_venue} ->
          Logger.info("Successfully updated venue #{venue.id} with #{length(updated_venue.google_place_images)} images")
        {:error, reason} ->
          Logger.error("Failed to update venue #{venue.id}: #{inspect(reason)}")
      end
    end)

    Logger.info("Finished fixing Google Place images for #{length(venues_to_fix)} venues")
  end

  # Find venues with Google Place images missing local paths
  defp find_venues_with_missing_local_paths(limit) do
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
end

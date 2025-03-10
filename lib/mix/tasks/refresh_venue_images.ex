defmodule Mix.Tasks.RefreshVenueImages do
  @moduledoc """
  Mix task to refresh Google Place images for specific venues by slug.

  ## Examples

      mix refresh_venue_images munich-cricket-club-tower-hill

  """

  use Mix.Task
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @shortdoc "Refresh Google Place images for venues by slug"

  def run(args) do
    # Start apps
    [:postgrex, :ecto, :trivia_advisor]
    |> Enum.each(&Application.ensure_all_started/1)

    if Enum.empty?(args) do
      Logger.error("❌ Please provide a venue slug")
      Logger.info("   Example: mix refresh_venue_images munich-cricket-club-tower-hill")
      System.halt(1)
    end

    slug = List.first(args)

    # Find venue by slug
    venue = Repo.get_by(Venue, slug: slug)

    if venue do
      Logger.info("🔍 Found venue: #{venue.name}")

      # Process venue images
      case GooglePlaceImageStore.process_venue_images(venue) do
        {:ok, updated_venue} ->
          image_count = length(updated_venue.google_place_images)
          Logger.info("✅ Successfully updated #{venue.name} with #{image_count} photo references")

        {:error, reason} ->
          Logger.error("❌ Failed to update venue images: #{inspect(reason)}")
      end
    else
      Logger.error("❌ Venue not found with slug: #{slug}")
    end
  end
end

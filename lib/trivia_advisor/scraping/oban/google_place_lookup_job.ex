defmodule TriviaAdvisor.Scraping.Oban.GooglePlaceLookupJob do
  @moduledoc """
  Generic Oban job for handling Google Places API interactions for venues across all scrapers.

  This job separates expensive Google Places API calls from the main venue processing
  flow, allowing us to:
  1. Properly track and monitor Google API usage
  2. Rate limit these expensive calls independently
  3. Apply different retry strategies for API failures

  Usage:
  ```
  %{"venue_id" => venue.id}
  |> GooglePlaceLookupJob.new()
  |> Oban.insert()
  ```
  """

  use Oban.Worker,
    queue: :google_api,
    max_attempts: 3,
    priority: 1

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id}}) do
    venue = Repo.get(Venue, venue_id)

    if venue do
      Logger.info("🔍 Processing Google Place lookup for venue: #{venue.name}")

      # Use the GooglePlaceImageStore service to update venue images
      updated_venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

      case updated_venue do
        %Venue{} = updated ->
          image_count = if updated.google_place_images, do: length(updated.google_place_images), else: 0

          Logger.info("✅ Successfully updated Google Place data for venue #{venue.name} with #{image_count} images")
          {:ok, %{venue_id: venue.id, image_count: image_count}}

        nil ->
          Logger.warning("⚠️ No updates needed for venue: #{venue.name}")
          {:ok, %{venue_id: venue.id, skipped: true}}
      end
    else
      Logger.error("❌ Venue not found with ID: #{venue_id}")
      {:error, :venue_not_found}
    end
  end
end

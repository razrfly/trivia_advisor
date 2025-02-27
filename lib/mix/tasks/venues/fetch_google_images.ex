defmodule Mix.Tasks.Venues.FetchGoogleImages do
  use Mix.Task
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Services.GooglePlaceImageStore
  import Ecto.Query

  @shortdoc "Fetches and stores Google Place images for venues"
  @moduledoc """
  Fetches images from the Google Places API for venues that have a place_id,
  stores them physically, and updates the venues with image metadata.

  ## Command-line options

    * `--limit` - Maximum number of venues to process (default: 100)
    * `--city` - Process only venues from this city slug
    * `--force` - Re-fetch images even if venue already has images

  ## Examples

      # Process up to 100 venues
      mix venues.fetch_google_images

      # Process up to 50 venues from London
      mix venues.fetch_google_images --limit=50 --city=london

      # Re-fetch images for all venues from Manchester
      mix venues.fetch_google_images --city=manchester --force
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [
      limit: :integer,
      city: :string,
      force: :boolean
    ])

    limit = Keyword.get(opts, :limit, 100)
    city_slug = Keyword.get(opts, :city)
    force = Keyword.get(opts, :force, false)

    # Start the application
    Mix.Task.run("app.start")

    # Build query based on options
    query = Venue
    |> where([v], not is_nil(v.place_id) and v.place_id != "")
    |> limit(^limit)

    # Add city filter if provided
    query = if city_slug do
      Mix.shell().info("Filtering venues by city: #{city_slug}")
      query |> join(:inner, [v], c in assoc(v, :city), on: c.slug == ^city_slug)
    else
      query
    end

    # Add filter to exclude venues that already have images unless force mode is enabled
    query = if not force do
      Mix.shell().info("Skipping venues that already have Google Place images")
      query |> where([v], fragment("coalesce(jsonb_array_length(?), 0) = 0", v.google_place_images))
    else
      Mix.shell().info("Processing all venues (force mode)")
      query
    end

    # Execute query
    venues = Repo.all(query)
    total = length(venues)

    if total == 0 do
      Mix.shell().info("No venues found matching the criteria.")
    else
      Mix.shell().info("Found #{total} venues to process.")

      # Process venues and collect results
      results = Enum.map(venues, fn venue ->
        Mix.shell().info("Processing venue: #{venue.name} (#{venue.id})")

        case GooglePlaceImageStore.process_venue_images(venue) do
          {:ok, updated_venue} ->
            image_count = length(updated_venue.google_place_images)
            if image_count > 0 do
              Mix.shell().info("✅ Successfully stored #{image_count} images for #{venue.name}")
              {:ok, venue.id}
            else
              Mix.shell().info("⚠️ No images found for #{venue.name}")
              {:no_images, venue.id}
            end

          {:error, reason} ->
            Mix.shell().error("❌ Failed to process venue #{venue.id}: #{inspect(reason)}")
            {:error, venue.id, reason}
        end
      end)

      # Summarize results
      successful = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      no_images = Enum.count(results, fn
        {:no_images, _} -> true
        _ -> false
      end)

      errors = Enum.count(results, fn
        {:error, _, _} -> true
        _ -> false
      end)

      Mix.shell().info("""

      📊 Summary:
        Total venues processed: #{total}
        Successful: #{successful}
        No images found: #{no_images}
        Errors: #{errors}
      """)
    end
  end
end

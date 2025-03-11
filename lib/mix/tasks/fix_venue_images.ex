defmodule Mix.Tasks.FixVenueImages do
  @moduledoc """
  Mix task to fix missing images for venues.

  ## Examples

  # Fix images for all venues from a particular source:
  mix fix_venue_images --source=question_one

  # Fix images for specific venues by name (partial matches work):
  mix fix_venue_images --name="Bull, Islington"
  mix fix_venue_images --name="Coopers Arms"

  # Fix images for a limited number of venues:
  mix fix_venue_images --source=question_one --limit=10

  # Force recreation of images even if they exist:
  mix fix_venue_images --source=question_one --force
  """

  use Mix.Task
  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Events.{Event, EventSource}
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Services.GooglePlaceImageStore

  @shortdoc "Fix missing images for venues"

  @impl Mix.Task
  def run(args) do
    # Parse command line options
    {opts, _, _} = OptionParser.parse(args,
      switches: [
        source: :string,
        name: :string,
        limit: :integer,
        force: :boolean
      ]
    )

    source_name = Keyword.get(opts, :source)
    venue_name = Keyword.get(opts, :name)
    limit = Keyword.get(opts, :limit, 100)
    force = Keyword.get(opts, :force, false)

    if is_nil(source_name) && is_nil(venue_name) do
      Logger.error("""
      ❌ Please specify either a source or venue name:

      mix fix_venue_images --source=question_one
      mix fix_venue_images --name="Bull, Islington"
      """)
      exit({:shutdown, 1})
    end

    # Start required applications
    [:postgrex, :ecto, :trivia_advisor]
    |> Enum.each(&Application.ensure_all_started/1)

    venues = get_venues(source_name, venue_name, limit)

    if Enum.empty?(venues) do
      Logger.error("❌ No matching venues found")
      exit({:shutdown, 1})
    end

    Logger.info("🔍 Found #{length(venues)} venues to process")

    # Process each venue
    success_count = process_venues(venues, force)

    Logger.info("✅ Successfully updated #{success_count} out of #{length(venues)} venues")
  end

  defp get_venues(source_name, venue_name, limit) do
    base_query = from v in Venue,
                 where: not is_nil(v.place_id) and v.place_id != ""

    query = cond do
      source_name && venue_name ->
        source = get_source_by_name(source_name)
        if source do
          from v in base_query,
          where: ilike(v.name, ^"%#{venue_name}%"),
          join: e in Event, on: e.venue_id == v.id,
          join: es in EventSource, on: es.event_id == e.id,
          where: es.source_id == ^source.id,
          limit: ^limit
        else
          from v in base_query,
          where: ilike(v.name, ^"%#{venue_name}%"),
          limit: ^limit
        end

      source_name ->
        source = get_source_by_name(source_name)
        if source do
          from v in base_query,
          join: e in Event, on: e.venue_id == v.id,
          join: es in EventSource, on: es.event_id == e.id,
          where: es.source_id == ^source.id,
          limit: ^limit
        else
          base_query |> limit(^limit)
        end

      venue_name ->
        from v in base_query,
        where: ilike(v.name, ^"%#{venue_name}%"),
        limit: ^limit

      true ->
        base_query |> limit(^limit)
    end

    Repo.all(query)
  end

  defp get_source_by_name(name) do
    cond do
      name == "question_one" -> Repo.get_by(Source, slug: "question-one")
      name == "inquizition" -> Repo.get_by(Source, slug: "inquizition")
      name == "speed_quizzing" -> Repo.get_by(Source, slug: "speed-quizzing")
      name == "quizmeisters" -> Repo.get_by(Source, slug: "quizmeisters")
      name == "geeks_who_drink" -> Repo.get_by(Source, slug: "geeks-who-drink")
      true -> nil
    end
  end

  defp process_venues(venues, force) do
    venues
    |> Enum.map(fn venue ->
      missing_images = GooglePlaceImageStore.missing_or_few_images?(venue)

      if missing_images || force do
        Logger.info("🔄 Processing venue: #{venue.name}")

        case GooglePlaceImageStore.process_venue_images(venue) do
          {:ok, _updated_venue} ->
            Logger.info("✅ Successfully updated #{venue.name} with Google Place images")
            true
          {:error, reason} ->
            Logger.error("❌ Failed to update #{venue.name}: #{inspect(reason)}")
            false
        end
      else
        Logger.info("⏭️ Skipping venue with images: #{venue.name}")
        true
      end
    end)
    |> Enum.count(& &1)
  end
end

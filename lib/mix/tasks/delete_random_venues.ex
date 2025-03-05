defmodule Mix.Tasks.DeleteRandomVenues do
  use Mix.Task

  @shortdoc "Deletes a random set of venues from a specific scraper source"

  require Logger
  import Ecto.Query, warn: false

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Events.{Event, EventSource}
  alias TriviaAdvisor.Scraping.Source

  @default_count 5

  @scraper_sources %{
    "inquizition" => "inquizition",
    "question_one" => "question-one",
    "speed_quizzing" => "speed-quizzing"
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [scraper_name] ->
        delete_random_venues(scraper_name, @default_count)

      [scraper_name, count] ->
        case Integer.parse(count) do
          {num, ""} when num > 0 ->
            delete_random_venues(scraper_name, num)

          _ ->
            Logger.error("❌ Invalid number of venues to delete. Provide a positive integer.")
        end

      _ ->
        Logger.error("""
        ❌ Invalid usage. Correct format:
          mix delete_random_venues [scraper_name] [optional: count]

        Example:
          mix delete_random_venues inquizition 5

        Available scrapers: #{Enum.join(Map.keys(@scraper_sources), ", ")}
        """)
    end
  end

  defp delete_random_venues(scraper_name, count) do
    source_slug = Map.get(@scraper_sources, scraper_name)

    if source_slug do
      # Fetch the source by slug
      case Repo.get_by(Source, slug: source_slug) do
        nil ->
          Logger.error("❌ No source found for scraper '#{scraper_name}'")

        source ->
          # Find venues associated with this source through events and event_sources
          subquery =
            from es in EventSource,
            where: es.source_id == ^source.id,
            join: e in Event, on: es.event_id == e.id,
            select: e.venue_id

          query =
            from v in Venue,
            where: v.id in subquery(subquery),
            order_by: fragment("RANDOM()"),
            limit: ^count,
            select: {v.id, v.name, v.address}

          venues = Repo.all(query)

          case venues do
            [] ->
              Logger.info("ℹ️ No venues found for '#{scraper_name}', nothing to delete.")

            _ ->
              venue_ids = Enum.map(venues, fn {id, _, _} -> id end)

              # Prepare a user-friendly summary of venues to be deleted
              venue_details = Enum.map_join(venues, "\n", fn {_, name, address} ->
                "  - #{name} (#{address})"
              end)

              # Delete venues one by one to ensure before_delete callbacks are invoked
              {deleted_count, failed_ids} = Enum.reduce(venue_ids, {0, []}, fn id, {count, failed} ->
                venue = Repo.get(Venue, id)

                if venue do
                  case Repo.delete(venue) do
                    {:ok, _} -> {count + 1, failed}
                    {:error, _} -> {count, [id | failed]}
                  end
                else
                  {count, failed}
                end
              end)

              if deleted_count > 0 do
                Logger.info("""
                ✅ Successfully deleted #{deleted_count} venues for '#{scraper_name}':
                #{venue_details}
                """)
              end

              if length(failed_ids) > 0 do
                Logger.error("❌ Failed to delete #{length(failed_ids)} venues: #{inspect(failed_ids)}")
              end
          end
      end
    else
      Logger.error("""
      ❌ Invalid scraper name. Available scrapers: #{Enum.join(Map.keys(@scraper_sources), ", ")}
      """)
    end
  end
end

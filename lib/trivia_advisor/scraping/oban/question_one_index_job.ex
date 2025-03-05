defmodule TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob do
  use Oban.Worker, queue: :default

  require Logger

  # Aliases for Question One scraper functionality
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source

  @base_url "https://questionone.com"
  @feed_url "#{@base_url}/venues/feed/"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting Question One Index Job...")

    # Check if a limit is specified (for testing)
    limit = Map.get(args, "limit")

    # Get the Question One source
    source = Repo.get_by!(Source, website_url: @base_url)

    # Call the existing scrape_feed function to get the event list
    case scrape_feed(1, []) do
      [] ->
        Logger.error("❌ No venues found in Question One feed")
        {:error, "No venues found"}

      venues when is_list(venues) ->
        # Log the number of venues found
        venue_count = length(venues)
        Logger.info("✅ Successfully fetched #{venue_count} venues from Question One feed")

        # Apply limit if specified
        venues_to_process = if limit, do: Enum.take(venues, limit), else: venues
        limited_count = length(venues_to_process)

        if limit do
          Logger.info("🧪 Testing mode: Limited to #{limited_count} venues (out of #{venue_count} total)")
        end

        # Enqueue detail jobs for each venue
        enqueued_count = enqueue_detail_jobs(venues_to_process, source.id)
        Logger.info("✅ Enqueued #{enqueued_count} detail jobs for processing")

        # Return success with venue count
        {:ok, %{venue_count: venue_count, enqueued_jobs: enqueued_count, source_id: source.id}}

      {:error, reason} ->
        # Log the error
        Logger.error("❌ Failed to fetch Question One venues: #{inspect(reason)}")

        # Return the error
        {:error, reason}
    end
  end

  # Enqueue detail jobs for each venue
  defp enqueue_detail_jobs(venues, source_id) do
    Logger.info("🔄 Enqueueing detail jobs for #{length(venues)} venues...")

    # For each venue, create a detail job with the URL and title
    Enum.reduce(venues, 0, fn venue, count ->
      url = Map.get(venue, :url)
      title = Map.get(venue, :title)

      if is_nil(url) do
        Logger.warning("⚠️ Skipping venue with missing URL: #{inspect(venue)}")
        count
      else
        # Create a job with the venue URL, title, and source ID
        %{
          url: url,
          title: title,
          source_id: source_id
        }
        |> TriviaAdvisor.Scraping.Oban.QuestionOneDetailJob.new()
        |> Oban.insert()
        |> case do
          {:ok, _job} -> count + 1
          {:error, error} ->
            Logger.error("❌ Failed to enqueue detail job for venue #{title}: #{inspect(error)}")
            count
        end
      end
    end)
  end

  # The following functions are adapted from the Question One scraper
  # to avoid modifying the original code

  defp scrape_feed(page, acc) do
    url = if page == 1, do: @feed_url, else: "#{@feed_url}?paged=#{page}"
    Logger.info("Fetching page #{page}: #{url}")

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case parse_feed(body) do
          [] ->
            Logger.info("No venues found on page #{page}, stopping")
            acc
          venues ->
            Logger.info("Found #{length(venues)} venues on page #{page}")
            venues |> Enum.each(&log_venue/1)
            # Continue to next page
            scrape_feed(page + 1, acc ++ venues)
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.info("Reached end at page #{page}")
        acc

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} on page #{page}")
        acc

      {:error, error} ->
        Logger.error("Error fetching page #{page}: #{inspect(error)}")
        acc
    end
  end

  defp parse_feed(body) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        document
        |> Floki.find("item")
        |> Enum.map(fn item ->
          %{
            title: item |> Floki.find("title") |> Floki.text() |> String.trim() |> HtmlEntities.decode(),
            url: item |> Floki.find("link") |> Floki.text() |> String.trim() |> clean_url()
          }
        end)
      {:error, reason} ->
        Logger.error("Failed to parse feed: #{inspect(reason)}")
        []
    end
  end

  defp clean_url(url) do
    url
    |> String.split("?")
    |> List.first()
    |> String.trim()
  end

  defp log_venue(%{title: title, url: url}) do
    Logger.info("""
    Found Venue:
      Title: #{title}
      URL: #{url}
    """)
  end
end

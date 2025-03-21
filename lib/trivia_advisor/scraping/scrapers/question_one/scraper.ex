defmodule TriviaAdvisor.Scraping.Scrapers.QuestionOne do
  @moduledoc """
  Scraper for QuestionOne venues and events.

  DEPRECATED: This legacy scraper is deprecated in favor of Oban jobs.
  Please use TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob instead.
  """

  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Repo
  require Logger
  alias TriviaAdvisor.Scraping.Scrapers.QuestionOne.VenueExtractor
  alias TriviaAdvisor.Services.GooglePlaceImageStore
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

  @base_url "https://questionone.com"
  @feed_url "#{@base_url}/venues/feed/"

  @type venue_data :: %{
    name: String.t(),
    address: String.t(),
    phone: String.t() | nil,
    website: String.t() | nil
  }

  @doc """
  Main entry point for the scraper.

  DEPRECATED: Please use TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob instead.
  """
  def run do
    Logger.warning("⚠️ DEPRECATED: This legacy scraper is deprecated. Please use TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob instead.")
    source = Repo.get_by!(Source, website_url: @base_url)
    start_time = DateTime.utc_now()

    try do
      Logger.info("Starting RSS feed scrape")
      venues = scrape_feed(1, [])

      detailed_venues = venues
      |> Enum.map(&fetch_venue_details/1)
      |> Enum.reject(&is_nil/1)

      venue_count = length(detailed_venues)
      Logger.info("Completed scraping #{venue_count} total venues")

      # Convert venues to simple maps for JSON encoding
      venue_maps = Enum.map(detailed_venues, fn venue ->
        %{
          id: venue.id,
          name: venue.name,
          address: venue.address,
          postcode: venue.postcode,
          phone: venue.phone,
          website: venue.website
        }
      end)

      # Log summary of scrape results
      Logger.info("""
      📊 QuestionOne Scrape Summary:
      - Total venues: #{venue_count}
      - Started at: #{DateTime.to_iso8601(start_time)}
      - Completed at: #{DateTime.to_iso8601(DateTime.utc_now())}
      """)

      {:ok, detailed_venues}
    rescue
      e ->
        Logger.error("Scraper failed: #{Exception.message(e)}")
        {:error, e}
    end
  end

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
    {:ok, document} = Floki.parse_document(body)

    document
    |> Floki.find("item")
    |> Enum.map(fn item ->
      %{
        title: item |> Floki.find("title") |> Floki.text() |> String.trim() |> HtmlEntities.decode(),
        url: item |> Floki.find("link") |> Floki.text() |> String.trim() |> clean_url()
      }
    end)
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

  defp fetch_venue_details(%{url: url, title: raw_title}) do
    Logger.info("\n🔍 Processing venue: #{raw_title}")

    source = Repo.get_by!(Source, website_url: @base_url)

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, document} <- Floki.parse_document(body),
             {:ok, extracted_data} <- VenueExtractor.extract_venue_data(document, url, raw_title),
             true <- String.length(extracted_data.title) > 0 || {:error, :empty_title},
             true <- String.length(extracted_data.address) > 0 || {:error, :empty_address} do

          # First process the venue
          venue_data = %{
            name: extracted_data.title,
            address: extracted_data.address,
            phone: extracted_data.phone,
            website: extracted_data.website
          }

          with {:ok, venue} <- TriviaAdvisor.Locations.VenueStore.process_venue(venue_data) do
            # Check if we should fetch Google Place images using the centralized function
            venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

            # Then process the event with the venue

            # Process the hero image using the centralized ImageDownloader
            hero_image_attrs = if extracted_data.hero_image_url && extracted_data.hero_image_url != "" do
              case ImageDownloader.download_event_hero_image(extracted_data.hero_image_url) do
                {:ok, upload} ->
                  Logger.info("✅ Successfully downloaded hero image for #{venue.name}")
                  %{hero_image: upload}
                {:error, reason} ->
                  Logger.warning("⚠️ Failed to download hero image for #{venue.name}: #{inspect(reason)}")
                  %{}
              end
            else
              Logger.debug("ℹ️ No hero image URL provided for venue: #{venue.name}")
              %{}
            end

            event_data = %{
              raw_title: raw_title,
              name: venue.name,
              time_text: extracted_data.time_text,
              description: extracted_data.description,
              fee_text: extracted_data.fee_text,
              source_url: url
            } |> Map.merge(hero_image_attrs)  # Merge the hero_image if we have it

            case TriviaAdvisor.Events.EventStore.process_event(venue, event_data, source.id) do
              {:ok, _event} ->
                Logger.info("✅ Successfully processed event for venue: #{venue.name}")
                venue
              {:error, reason} ->
                Logger.error("❌ Failed to process event: #{inspect(reason)}")
                nil
            end
          else
            {:error, reason} ->
              Logger.error("❌ Failed to process venue: #{inspect(reason)}")
              nil
          end
        else
          {:ok, %{title: _title} = data} ->
            Logger.error("❌ Missing required address in extracted data: #{inspect(data)}")
            nil
          {:error, :empty_title} ->
            Logger.error("❌ Empty title for venue: #{raw_title}")
            nil
          {:error, :empty_address} ->
            Logger.error("❌ Empty address for venue: #{raw_title}")
            nil
          error ->
            Logger.error("""
            ❌ Failed to process venue: #{raw_title}
            Reason: #{inspect(error)}
            URL: #{url}
            """)
            nil
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching venue: #{url}")
        nil

      {:error, error} ->
        Logger.error("❌ Error fetching venue #{url}: #{inspect(error)}")
        nil
    end
  end
end

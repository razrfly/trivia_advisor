defmodule TriviaAdvisor.Scraping.Scrapers.QuestionOne do
  @moduledoc """
  Scraper for QuestionOne venues and events.
  """

  alias TriviaAdvisor.Scraping.{ScrapeLog, Source}
  alias TriviaAdvisor.Repo
  require Logger

  @base_url "https://questionone.com"
  @feed_url "#{@base_url}/venues/feed/"

  @doc """
  Main entry point for the scraper.
  """
  def run do
    source = Repo.get_by!(Source, website_url: @base_url)

    case ScrapeLog.create_log(source) do
      {:ok, log} ->
        try do
          Logger.info("Starting RSS feed scrape")
          venues = scrape_feed(1, [])

          detailed_venues = venues
          |> Enum.map(&fetch_venue_details/1)
          |> Enum.reject(&is_nil/1)

          venue_count = length(detailed_venues)
          Logger.info("Completed scraping #{venue_count} total venues")

          ScrapeLog.update_log(log, %{
            success: true,
            event_count: venue_count,
            metadata: %{
              total_venues: venue_count,
              venues: detailed_venues,
              completed_at: DateTime.utc_now()
            }
          })

          {:ok, detailed_venues}
        rescue
          e ->
            ScrapeLog.log_error(log, e)
            Logger.error("Scraper failed: #{Exception.message(e)}")
            {:error, e}
        end

      {:error, reason} ->
        Logger.error("Failed to create scrape log: #{inspect(reason)}")
        {:error, reason}
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

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, document} <- Floki.parse_document(body),
@type venue_data :: %{
  name: String.t(),
  address: String.t(),
  phone: String.t() | nil,
  website: String.t() | nil
}

with {:ok, %{title: title, address: address} = extracted_data} <- TriviaAdvisor.Scraping.VenueExtractor.extract_venue_data(document, url, raw_title),
     true <- String.length(title) > 0 || {:error, :empty_title},
     true <- String.length(address) > 0 || {:error, :empty_address},
     venue_data = %{
       name: title,
       address: address,
       phone: Map.get(extracted_data, :phone),
       website: Map.get(extracted_data, :website)
     } |> tap(fn data -> 
           if is_nil(data.phone), do: Logger.info("ℹ️ No phone number for venue: #{title}")
           if is_nil(data.website), do: Logger.info("ℹ️ No website for venue: #{title}")
         end),
     {:ok, venue} <- TriviaAdvisor.Locations.VenueStore.process_venue(venue_data) do
  ...
end
          venue
        else
          {:ok, %{title: _title} = data} ->
            Logger.error("❌ Missing required address in extracted data: #{inspect(data)}")
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

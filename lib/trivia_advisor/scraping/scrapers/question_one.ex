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
          |> Enum.map(fn venue ->
            Process.sleep(1000) # Be nice to their server
            fetch_venue_details(venue)
          end)
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
            Process.sleep(1000) # Be nice to their server
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
    Logger.info("\n🔍 Processing venue: #{url}")

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, document} = Floki.parse_document(body)
        extract_venue_data(document, url, raw_title)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} when fetching venue: #{url}")
        nil

      {:error, error} ->
        Logger.error("Error fetching venue #{url}: #{inspect(error)}")
        nil
    end
  end

  defp extract_venue_data(document, url, raw_title) do
    # Clean the title - remove PUB QUIZ prefix and everything after dash
    title = raw_title
    |> String.replace(~r/^PUB QUIZ[[:punct:]]*/i, "")
    |> String.replace(~r/^[–\s]+/, "")
    |> String.replace(~r/\s+[–].*$/i, "")
    |> String.trim()

    # Extract data using icon-based selectors
    address = find_text_with_icon(document, "pin")
    time_text = find_text_with_icon(document, "calendar")
    fee_text = find_text_with_icon(document, "tag")
    phone = find_text_with_icon(document, "phone")

    # Extract website link
    website = document
    |> Floki.find("a[href]:fl-contains('Visit Website')")
    |> Floki.attribute("href")
    |> List.first()

    # Extract description
    description = document
    |> Floki.find(".post-content-area p")
    |> Enum.map(&Floki.text/1)
    |> Enum.join("\n\n")
    |> String.trim()

    # Extract hero image
    hero_image_url = document
    |> Floki.find("img[src*='wp-content/uploads']")
    |> Floki.attribute("src")
    |> List.first()

    venue_data = %{
      raw_title: raw_title,
      title: title,
      address: address,
      time_text: time_text,
      fee_text: fee_text,
      phone: phone,
      website: website,
      description: description,
      hero_image_url: hero_image_url,
      url: url
    }

    log_venue_details(venue_data)
    venue_data
  end

  defp find_text_with_icon(document, icon_name) do
    document
    |> Floki.find(".text-with-icon")
    |> Enum.find(fn el ->
      Floki.find(el, "use")
      |> Enum.any?(fn use ->
        href = Floki.attribute(use, "href") |> List.first()
        xlink = Floki.attribute(use, "xlink:href") |> List.first()
        (href && String.ends_with?(href, "##{icon_name}")) ||
        (xlink && String.ends_with?(xlink, "##{icon_name}"))
      end)
    end)
    |> case do
      nil -> nil
      el -> el |> Floki.find(".text-with-icon__text") |> Floki.text() |> String.trim()
    end
  end

  defp log_venue_details(venue) do
    Logger.info("""
    Extracted Venue Data:
      Raw Title: #{inspect(venue.raw_title)}
      Cleaned Title: #{inspect(venue.title)}
      Address: #{inspect(venue.address)}
      Time: #{inspect(venue.time_text)}
      Fee: #{inspect(venue.fee_text)}
      Phone: #{inspect(venue.phone)}
      Website: #{inspect(venue.website)}
      Description: #{inspect(String.slice(venue.description || "", 0..100))}
      Hero Image: #{inspect(venue.hero_image_url)}
    """)
  end
end

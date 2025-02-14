defmodule TriviaAdvisor.Scraping.Scrapers.QuestionOne do
  @moduledoc """
  Scraper for QuestionOne venues and events.
  """

  alias TriviaAdvisor.Scraping.{ScrapeLog, Source, VenueExtractor}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Repo
  require Logger

  @base_url "https://questionone.com"
  @feed_url "#{@base_url}/venues/feed/"

  @doc """
  Main entry point for the scraper.
  Scrapes venues and events, storing them in the database.
  """
  def run do
    source = Repo.get_by!(Source, website_url: @base_url)

    case ScrapeLog.create_log(source) do
      {:ok, log} ->
        try do
          Logger.info("Starting RSS feed scrape")
          venues = scrape_feed(1, [])

          {stored_venues, failed_venues} = venues
          |> Task.async_stream(
            fn venue ->
              Process.sleep(1000) # Be nice to their server
              case fetch_venue_details(venue) do
                {:ok, stored_venue} ->
                  Logger.info("""
                  ✅ Successfully processed venue:
                     Name: #{stored_venue.name}
                     URL: #{venue.url}
                  """)
                  {:ok, stored_venue, venue}

                {:error, reason} ->
                  Logger.error("""
                  ❌ Failed to process venue:
                     Title: #{venue.title}
                     URL: #{venue.url}
                     Reason: #{inspect(reason)}
                  """)
                  {:error, reason, venue}
              end
            end,
            max_concurrency: 2,
            ordered: false
          )
          |> Enum.reduce({[], []}, fn
            {:ok, {:ok, venue, _source}}, {stored, failed} -> {[venue | stored], failed}
            {:ok, {:error, reason, source}}, {stored, failed} -> {stored, [{reason, source.url} | failed]}
            {:exit, reason}, {stored, failed} -> {stored, [{:task_crashed, reason, "Unknown URL"} | failed]}
          end)

          venue_count = length(stored_venues)
          failed_count = length(failed_venues)

          Logger.info("""
          📊 Scraping Summary:
          ✅ #{venue_count} venues stored successfully
          ❌ #{failed_count} venues failed

          Failed Venues:
          #{format_failed_venues(failed_venues)}
          """)

          ScrapeLog.update_log(log, %{
            success: true,
            event_count: venue_count,
            metadata: %{
              total_venues: venue_count + failed_count,
              stored_venues: stored_venues,
              failed_venues: failed_venues,
              completed_at: DateTime.utc_now()
            }
          })

          {:ok, stored_venues}
        rescue
          e ->
            Logger.error("""
            💥 Scraper crashed:
            Error: #{Exception.message(e)}
            Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}
            """)
            ScrapeLog.log_error(log, e)
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
        with {:ok, document} <- Floki.parse_document(body),
             {:ok, extracted_data} <- VenueExtractor.extract_venue_data(document, url, raw_title),
             venue_data = transform_venue_data(extracted_data),
             :ok <- validate_venue_data(venue_data) do

          # Fill in missing optional fields with defaults
          venue_data = fill_missing_defaults(venue_data)

          case VenueStore.process_venue(venue_data) do
            {:ok, stored_venue} ->
              Logger.info("""
              ✅ Successfully stored venue:
                 Name: #{stored_venue.name}
                 Address: #{stored_venue.address}
                 URL: #{url}
              """)
              {:ok, stored_venue}

            {:error, reason} ->
              Logger.error("""
              ❌ Failed to store venue:
              Name: #{venue_data.name}
              URL: #{url}
              Reason: #{inspect(reason)}
              Data: #{inspect(venue_data)}
              """)
              {:error, reason}
          end
        else
          {:error, :invalid_venue_data, reason} ->
            Logger.error("""
            ❌ Invalid venue data:
            URL: #{url}
            Title: #{raw_title}
            Reason: #{reason}
            """)
            {:error, :invalid_venue_data}

          {:error, reason} ->
            Logger.error("""
            ❌ Failed to process venue: #{raw_title}
            URL: #{url}
            Reason: #{inspect(reason)}
            """)
            {:error, reason}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching venue: #{url}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("❌ Error fetching venue #{url}: #{inspect(error)}")
        {:error, error}
    end
  end

  # Transform extracted data to match VenueStore schema
  defp transform_venue_data(extracted) do
    %{
      name: extracted.title || extracted.raw_title || "Unknown Venue",
      address: extracted.address || "Unknown Address",
      phone: extracted.phone,
      website: extracted.website,
      hero_image: extracted.hero_image_url,
      description: extracted.description,
      fee: extracted.fee_text,
      time: extracted.time_text
    }
  end

  # Only validate required fields (name and address)
  defp validate_venue_data(%{name: name, address: address} = venue)
       when is_binary(name) and is_binary(address) do
    case {String.trim(name), String.trim(address)} do
      {"", _} ->
        Logger.error("❌ Empty venue name: #{inspect(venue)}")
        {:error, :invalid_venue_data, "Empty venue name"}
      {_, ""} ->
        Logger.error("❌ Empty venue address: #{inspect(venue)}")
        {:error, :invalid_venue_data, "Empty venue address"}
      _ -> :ok
    end
  end

  defp validate_venue_data(%{name: nil} = venue) do
    Logger.error("❌ Missing venue name: #{inspect(venue)}")
    {:error, :invalid_venue_data, "Missing venue name"}
  end

  defp validate_venue_data(%{address: nil} = venue) do
    Logger.error("❌ Missing venue address: #{inspect(venue)}")
    {:error, :invalid_venue_data, "Missing venue address"}
  end

  defp validate_venue_data(invalid_data) do
    Logger.error("❌ Invalid venue structure: #{inspect(invalid_data)}")
    {:error, :invalid_venue_data, "Invalid venue structure"}
  end

  # Fill in missing optional fields with defaults
  defp fill_missing_defaults(venue_data) do
    defaults = %{
      phone: nil,
      website: nil,
      hero_image_url: nil,
      description: nil
    }
    Map.merge(defaults, venue_data)
  end

  defp format_failed_venues(failed_venues) do
    failed_venues
    |> Enum.map(fn
      {reason, url} -> "  - #{url}: #{inspect(reason)}"
      {:task_crashed, reason, url} -> "  - #{url}: Task crashed - #{inspect(reason)}"
    end)
    |> Enum.join("\n")
  end
end

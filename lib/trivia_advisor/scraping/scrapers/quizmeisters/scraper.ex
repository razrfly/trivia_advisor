defmodule TriviaAdvisor.Scraping.Scrapers.Quizmeisters do
  @moduledoc """
  Scraper for Quizmeisters venues and events.
  """

  alias TriviaAdvisor.Scraping.{ScrapeLog, Source}
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers}
  alias TriviaAdvisor.{Events, Repo}
  require Logger

  @base_url "https://quizmeisters.com"
  @api_url "https://storerocket.io/api/user/kDJ3BbK4mn/locations"
  @version "1.0.0"

  @doc """
  Main entry point for the scraper.
  """
  def run do
    Logger.info("Starting Quizmeisters scraper")
    source = Repo.get_by!(Source, website_url: @base_url)
    start_time = DateTime.utc_now()

    case ScrapeLog.create_log(source) do
      {:ok, log} ->
        Logger.info("Created scrape log")
        try do
          case fetch_venues() do
            {:ok, venues} ->
              venue_count = length(venues)
              Logger.info("Found #{venue_count} venues")

              detailed_venues = venues
              |> Enum.map(&fetch_venue_details(&1, source))
              |> Enum.reject(&is_nil/1)

              successful_venues = length(detailed_venues)
              failed_venues = venue_count - successful_venues

              metadata = %{
                "venues" => detailed_venues,
                "started_at" => DateTime.to_iso8601(start_time),
                "completed_at" => DateTime.to_iso8601(DateTime.utc_now()),
                "total_venues" => venue_count,
                "successful_venues" => successful_venues,
                "failed_venues" => failed_venues,
                "scraper_version" => @version
              }

              ScrapeLog.update_log(log, %{
                success: true,
                total_venues: venue_count,
                metadata: metadata
              })

              {:ok, detailed_venues}

            {:error, reason} ->
              Logger.error("Scraping failed: #{reason}")
              {:error, reason}
          end
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

  defp fetch_venues do
    case HTTPoison.get(@api_url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => %{"locations" => locations}}} when is_list(locations) ->
            venues = Enum.map(locations, &parse_venue/1)
            {:ok, venues}

          {:error, reason} ->
            Logger.error("Failed to parse JSON response: #{inspect(reason)}")
            {:error, "Failed to parse JSON response"}

          _ ->
            Logger.error("Unexpected response format")
            {:error, "Unexpected response format"}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status}: Failed to fetch venues")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp parse_venue(location) do
    time_text = get_trivia_time(location)
    {day_of_week, start_time} = parse_opening_hours(time_text)

    venue_data = %{
      raw_title: location["name"],
      title: location["name"],
      address: location["address"],
      time_text: time_text,
      day_of_week: day_of_week,
      start_time: start_time,
      frequency: :weekly,
      fee_text: "Free", # All Quizmeisters events are free
      phone: location["phone"],
      website: nil, # Will be fetched from individual venue page
      description: nil, # Will be fetched from individual venue page
      hero_image: nil,
      hero_image_url: nil, # Will be fetched from individual venue page
      url: location["url"]
    }

    VenueHelpers.log_venue_details(venue_data)
    venue_data
  end

  defp fetch_venue_details(venue_data, source) do
    Logger.info("Processing venue: #{venue_data.title}")

    case HTTPoison.get(venue_data.url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, document} <- Floki.parse_document(body),
             {:ok, extracted_data} <- extract_venue_data(document, venue_data.url) do

          # Merge the extracted data with the API data
          merged_data = Map.merge(venue_data, extracted_data)
          VenueHelpers.log_venue_details(merged_data)
          merged_data

        else
          {:error, reason} ->
            Logger.error("Failed to extract venue data: #{reason}")
            venue_data
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} when fetching venue: #{venue_data.url}")
        venue_data

      {:error, error} ->
        Logger.error("Error fetching venue #{venue_data.url}: #{inspect(error)}")
        venue_data
    end
  end

  defp extract_venue_data(document, url) do
    try do
      # Extract description from the venue-specific description first
      description = document
        |> Floki.find(".venue-description.w-richtext:not(.trivia-generic):not(.bingo-generic):not(.survey-generic) p")
        |> Enum.map(&Floki.text/1)
        |> Enum.join("\n\n")
        |> String.trim()
        |> filter_lorem_ipsum()

      # If no venue-specific description, get the trivia generic one
      description = if description == "",
        do: document
          |> Floki.find(".venue-description.trivia-generic.w-richtext p")
          |> Enum.map(&Floki.text/1)
          |> Enum.join("\n\n")
          |> String.trim()
          |> filter_lorem_ipsum(),
        else: description

      # Extract hero image
      hero_image_url = document
        |> Floki.find(".venue-photo")
        |> Floki.attribute("src")
        |> List.first()

      # Extract website from the icon block
      website = document
        |> Floki.find(".icon-block a")
        |> Enum.find(fn el ->
          Floki.find(el, "img[alt*='website']") |> Enum.any?()
        end)
        |> case do
          nil -> nil
          el -> Floki.attribute(el, "href") |> List.first()
        end

      # Extract phone from the venue block
      phone = document
        |> Floki.find(".venue-block .paragraph")
        |> Enum.map(&Floki.text/1)
        |> Enum.find(fn text ->
          String.match?(text, ~r/^\+?[\d\s-]{8,}$/)
        end)
        |> case do
          nil -> nil
          number -> String.trim(number)
        end

      # Check if venue is on break
      on_break = document
        |> Floki.find(".on-break")
        |> Enum.any?()

      {:ok, %{
        description: description,
        website: website,
        hero_image_url: hero_image_url,
        on_break: on_break,
        phone: phone
      }}
    rescue
      e ->
        Logger.error("Failed to extract venue data from #{url}: #{Exception.message(e)}")
        {:error, "Failed to extract venue data: #{Exception.message(e)}"}
    end
  end

  defp filter_lorem_ipsum(text) when is_binary(text) do
    if String.starts_with?(text, "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore e"), do: "", else: text
  end
  defp filter_lorem_ipsum(_), do: ""

  defp get_trivia_time(location) do
    # Find trivia time in fields array
    fields = location["fields"] || []
    Enum.find_value(fields, "", fn field ->
      if field["name"] in ["Trivia", "Survey Says"], do: field["pivot_field_value"]
    end)
  end

  defp parse_opening_hours(time_text) when is_binary(time_text) do
    case TimeParser.parse_time_text(time_text) do
      {:ok, %{day_of_week: day, start_time: time}} -> {day, time}
      {:error, _} -> {nil, nil}
    end
  end
  defp parse_opening_hours(_), do: {nil, nil}
end

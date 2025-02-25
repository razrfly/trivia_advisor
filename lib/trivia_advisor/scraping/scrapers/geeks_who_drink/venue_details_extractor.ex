defmodule TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.VenueDetailsExtractor do
  @moduledoc """
  Extracts additional venue details from individual venue pages.
  """

  require Logger

  def extract_additional_details(url) when is_binary(url) do
    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        case Floki.parse_document(body) do
          {:ok, document} ->
            {:ok, parse_details(document)}
          error -> error
        end
      {:ok, %{status_code: status}} ->
        Logger.error("Failed to fetch venue details. Status: #{status}")
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        Logger.error("Failed to fetch venue details: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_details(document) do
    %{
      website: extract_website(document),
      phone: extract_phone(document),
      description: extract_description(document),
      fee_text: extract_fee(document),
      facebook: extract_social_link(document, "facebook"),
      instagram: extract_social_link(document, "instagram"),
      start_time: extract_start_time(document)
    }
  end

  defp extract_website(document) do
    document
    |> Floki.find(".venueHero__address a[href]:not([href*='maps.google.com'])")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_phone(document) do
    document
    |> Floki.find(".venueHero__phone")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      phone -> phone
    end
  end

  defp extract_description(document) do
    document
    |> Floki.find(".venue__description")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      desc -> desc
    end
  end

  defp extract_fee(document) do
    document
    |> Floki.find(".venue__fee")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      fee -> fee
    end
  end

  defp extract_social_link(document, platform) do
    document
    |> Floki.find(".venue__social a[href*='#{platform}']")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_start_time(document) do
    document
    |> Floki.find(".venueHero__time .time-moment")
    |> Floki.text()
    |> case do
      "" ->
        # Try to get the data-time attribute if text is empty
        document
        |> Floki.find(".venueHero__time .time-moment")
        |> Floki.attribute("data-time")
        |> List.first()
      time ->
        # Convert "7:30 pm" format to 24h time
        case Regex.run(~r/(\d+):(\d+)\s*(am|pm)/i, time) do
          [_, hour, min, period] ->
            hour = String.to_integer(hour)
            min = String.to_integer(min)
            hour = case {hour, String.downcase(period)} do
              {12, "am"} -> 0
              {12, "pm"} -> 12
              {h, "am"} -> h
              {h, "pm"} -> h + 12
            end
            {:ok, dt} = DateTime.new(~D[2000-01-01], Time.new!(hour, min, 0))
            DateTime.to_iso8601(dt)
          _ -> nil
        end
    end
  end
end

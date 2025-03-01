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
    # First, try to extract the visible time directly from the time-moment span
    visible_time = document
    |> Floki.find(".venueHero__time .time-moment")
    |> Floki.text()
    |> String.trim()

    # Log the extracted time for debugging
    Logger.debug("📅 Extracted visible time: #{inspect(visible_time)}")

    if visible_time && visible_time != "" do
      # Try to convert 12-hour time (7:00 pm) to 24-hour time (19:00)
      case Regex.run(~r/(\d+):(\d+)\s*(am|pm)/i, visible_time) do
        [_, hour_str, minute_str, period] ->
          hour = String.to_integer(hour_str)
          minute = String.to_integer(minute_str)

          hour = case String.downcase(period) do
            "pm" when hour < 12 -> hour + 12
            "am" when hour == 12 -> 0
            _ -> hour
          end

          # Format as HH:MM
          formatted_time = :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> to_string()
          Logger.debug("📅 Converted time: #{visible_time} -> #{formatted_time}")
          formatted_time
        _ ->
          # If regex fails, try TimeParser
          time_text = document
          |> Floki.find(".venueHero__time")
          |> Floki.text()
          |> String.trim()

          Logger.debug("📅 Falling back to parsing time_text: #{inspect(time_text)}")
          case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time(time_text) do
            {:ok, time_str} -> time_str
            _ ->
              Logger.debug("📅 Time parsing failed, using default time")
              "20:00"  # Default fallback
          end
      end
    else
      # Fallback to data-time attribute if visible time is not found
      Logger.debug("📅 No visible time found, trying data-time attribute")
      case document
      |> Floki.find(".venueHero__time .time-moment")
      |> Floki.attribute("data-time")
      |> List.first() do
        nil ->
          Logger.debug("📅 No data-time attribute found, using default time")
          "20:00"  # Default fallback
        data_time ->
          # Parse ISO 8601 datetime string
          Logger.debug("📅 Using data-time attribute: #{inspect(data_time)}")
          case DateTime.from_iso8601(data_time) do
            {:ok, datetime, _} ->
              # Convert UTC time to local time (assuming US Mountain Time, UTC-6)
              # This is a simplification - in a real app, you'd use proper time zone handling
              local_hour = rem(datetime.hour + 18, 24)  # UTC to Mountain Time (UTC-6)
              minute = datetime.minute
              formatted_time = :io_lib.format("~2..0B:~2..0B", [local_hour, minute]) |> to_string()
              Logger.debug("📅 Parsed from ISO: #{formatted_time} (converted from UTC #{datetime.hour}:#{minute})")
              formatted_time
            _ ->
              Logger.debug("📅 ISO parsing failed, using default time")
              "20:00"  # Default fallback
          end
      end
    end
  end
end

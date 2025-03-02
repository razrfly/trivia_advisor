defmodule TriviaAdvisor.Scraping.Scrapers.SpeedQuizzing.VenueExtractor do
  @moduledoc """
  Module for extracting venue data from SpeedQuizzing event pages.
  """

  require Logger

  @base_url "https://www.speedquizzing.com"
  @event_url_format "#{@base_url}/events/%{event_id}/"

  @doc """
  Fetches and extracts venue and event data from a specific SpeedQuizzing event page.
  """
  def extract(event_id) do
    Logger.info("🔍 Extracting venue data for event ID: #{event_id}")

    event_url = @event_url_format |> String.replace("%{event_id}", "#{event_id}")

    case HTTPoison.get(event_url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Floki.parse_document(body) do
          {:ok, document} ->
            venue_data = extract_venue_data(document, event_id)
            {:ok, venue_data}

          {:error, reason} ->
            Logger.error("❌ Failed to parse HTML document: #{inspect(reason)}")
            {:error, "Failed to parse HTML document"}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status}: Failed to fetch event page for ID #{event_id}")
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Request failed for event ID #{event_id}: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc false
  def extract_venue_data(document, event_id) do
    # Extract data from the HTML document
    title = extract_title(document)
    venue_name = extract_venue_name(document)
    address = extract_address(document)
    postcode = extract_postcode(address)
    {time, day, date} = parse_date_time(document)
    description = extract_description(document)
    latitude = extract_latitude(document)
    longitude = extract_longitude(document)

    # Return the extracted data as a map
    %{
      event_id: event_id,
      event_title: title,
      venue_name: venue_name,
      address: address,
      postcode: postcode,
      start_time: time,
      day_of_week: day,
      date: date,
      description: description,
      lat: latitude,
      lng: longitude,
      event_url: "https://www.speedquizzing.com/events/#{event_id}/"
    }
  end

  # Extract the title from the document
  defp extract_title(document) do
    case Floki.find(document, "meta[property='og:title']") |> Floki.attribute("content") do
      [content | _] ->
        # Extract the title from the content
        case Regex.run(~r/SpeedQuizzing Smartphone Pub Quiz • (.*?) •/, content) do
          [_, title] -> title
          _ -> extract_title_from_h1(document)
        end
      _ -> extract_title_from_h1(document)
    end
  end

  # Fallback method to extract title from h1
  defp extract_title_from_h1(document) do
    case Floki.find(document, "h1") |> Floki.text() do
      "" -> "Unknown"
      title -> title
    end
  end

  # Extract the venue name from the document
  defp extract_venue_name(document) do
    # First try to extract from the address line with the bold tag
    case Floki.find(document, "p.mb-0 b") do
      [] ->
        # If not found, try to extract from the meta description
        extract_venue_name_from_meta(document)
      [venue_element | _] ->
        venue_name = Floki.text(venue_element)
        if venue_name == "", do: extract_venue_name_from_meta(document), else: venue_name
    end
  end

  # Extract venue name from meta description
  defp extract_venue_name_from_meta(document) do
    case Floki.find(document, "meta[name='description']") |> Floki.attribute("content") do
      [content | _] ->
        # Extract venue name from content
        case Regex.run(~r/Join the fun at (.*?),/, content) do
          [_, venue_name] -> venue_name
          _ -> "Unknown"
        end
      _ -> "Unknown"
    end
  end

  # Extract the full address from the document
  defp extract_address(document) do
    case Floki.find(document, "p.mb-0") do
      elements when is_list(elements) and length(elements) > 0 ->
        # Find the element with the map marker icon
        Enum.find_value(elements, "Unknown", fn element ->
          html = Floki.raw_html(element)
          if String.contains?(html, "fa-map-marker") do
            # Extract text and clean up
            address_text = Floki.text(element)
            # Remove the venue name from the beginning
            case Regex.run(~r/^(.*?), (.*)$/, address_text) do
              [_, _venue_name, address] -> String.trim(address)
              _ -> address_text
            end
          else
            nil
          end
        end)
      _ -> "Unknown"
    end
  end

  # Extract postcode from address
  defp extract_postcode(address) do
    # UK postcodes generally follow patterns like: AA9A 9AA, A9A 9AA, A9 9AA, A99 9AA, AA9 9AA, AA99 9AA
    case Regex.run(~r/\b([A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}|[0-9]{5}(?:-[0-9]{4})?)\b/, address) do
      [postcode | _] -> postcode
      _ -> ""
    end
  end

  # Parse the date and time information
  defp parse_date_time(document) do
    Logger.debug("⏰ Finding date/time element...")

    # First try to find elements with the clock icon
    clock_elements = Floki.find(document, "p.mb-0")
                    |> Enum.filter(fn el ->
                       html = Floki.raw_html(el)
                       String.contains?(html, "fa-clock")
                    end)

    # Get the text from the first matching element
    date_time_text = case clock_elements do
      [first | _] ->
        text = Floki.text(first)
        Logger.debug("⏰ Found date/time text: '#{text}'")
        # Log each character with its code point for debugging
        text |> String.to_charlist() |> Enum.each(fn char ->
          Logger.debug("⏰ Character: '#{[char]}' (#{char})")
        end)
        text
      [] ->
        Logger.debug("⏰ No clock element found, trying og:title")
        try_extract_from_og_title(document)
    end

    try_extract_from_date_time(date_time_text)
  end

  # Extract date and time from the date_time_text
  defp try_extract_from_date_time(date_time_text) when is_binary(date_time_text) and date_time_text != "" do
    Logger.debug("⏰ Parsing date/time from: '#{date_time_text}'")

    # The bullet character is Unicode code point 8226 (•)
    bullet = <<226, 128, 162>>

    # Try to match 12-hour format with or without period (e.g., "8pm", "7.30PM")
    # First, try to extract just the time part
    time_pattern = ~r/^\s*(\d+(?:\.\d+)?(?:\s*[ap]m|\s*PM|\s*AM)|\d{1,2}:\d{2})/i

    # Then try to extract the day and date parts
    day_date_pattern = ~r/#{bullet}\s*([A-Za-z]+)\s*(\d+\s*[A-Za-z]+(?:\s*\d{4})?)/

    # Extract time
    time_match = Regex.run(time_pattern, date_time_text)
    # Extract day and date
    day_date_match = Regex.run(day_date_pattern, date_time_text)

    case {time_match, day_date_match} do
      {[_, time], [_, day, date]} ->
        # Check if time is in 12-hour format (contains am/pm)
        time_24h = if Regex.match?(~r/[ap]m|AM|PM/i, time) do
          # Convert 12-hour to 24-hour format
          converted = convert_12h_to_24h(time)
          Logger.debug("⏰ Matched 12-hour format: time='#{time}', converted to 24h='#{converted}'")
          converted
        else
          # Already in 24-hour format
          Logger.debug("⏰ Matched 24-hour format: time='#{time}'")
          time
        end

        Logger.debug("⏰ Extracted time='#{time_24h}', day='#{day}', date='#{date}'")
        {time_24h, day, date}

      {[_, time], nil} ->
        # We have time but no day/date
        time_24h = if Regex.match?(~r/[ap]m|AM|PM/i, time) do
          convert_12h_to_24h(time)
        else
          time
        end
        Logger.debug("⏰ Extracted time='#{time_24h}' but no day/date")
        {time_24h, "Unknown", "Unknown"}

      {nil, [_, day, date]} ->
        # We have day/date but no time
        Logger.debug("⏰ Extracted day='#{day}', date='#{date}' but no time")
        {"00:00", day, date}

      _ ->
        # Try a simpler approach - just look for patterns in the string
        cond do
          # Look for 12-hour format
          Regex.match?(~r/(\d+(?:\.\d+)?(?:\s*[ap]m|\s*PM|\s*AM))/i, date_time_text) ->
            [_, time] = Regex.run(~r/(\d+(?:\.\d+)?(?:\s*[ap]m|\s*PM|\s*AM))/i, date_time_text)
            time_24h = convert_12h_to_24h(time)

            # Try to extract day and date
            day = case Regex.run(~r/#{bullet}\s*([A-Za-z]+)/, date_time_text) do
              [_, day_match] -> day_match
              _ -> "Unknown"
            end

            date = case Regex.run(~r/#{day}\s*(\d+\s*[A-Za-z]+(?:\s*\d{4})?)/, date_time_text) do
              [_, date_match] -> date_match
              _ -> "Unknown"
            end

            Logger.debug("⏰ Simple extraction: time='#{time_24h}', day='#{day}', date='#{date}'")
            {time_24h, day, date}

          # Look for 24-hour format
          Regex.match?(~r/(\d{1,2}:\d{2})/, date_time_text) ->
            [_, time] = Regex.run(~r/(\d{1,2}:\d{2})/, date_time_text)

            # Try to extract day and date
            day = case Regex.run(~r/#{bullet}\s*([A-Za-z]+)/, date_time_text) do
              [_, day_match] -> day_match
              _ -> "Unknown"
            end

            date = case Regex.run(~r/#{day}\s*(\d+\s*[A-Za-z]+(?:\s*\d{4})?)/, date_time_text) do
              [_, date_match] -> date_match
              _ -> "Unknown"
            end

            Logger.debug("⏰ Simple extraction: time='#{time}', day='#{day}', date='#{date}'")
            {time, day, date}

          true ->
            Logger.debug("⏰ No time format matched in: '#{date_time_text}'")
            {"00:00", "Unknown", "Unknown"}
        end
    end
  end

  defp try_extract_from_date_time(_), do: {"00:00", "Unknown", "Unknown"}

  # Convert 12-hour format to 24-hour format
  defp convert_12h_to_24h(time_str) do
    Logger.debug("⏰ Converting 12h to 24h: '#{time_str}'")

    # Handle cases like "8pm", "8:30pm", "8 pm", "8:30 pm", "7.30PM"
    cond do
      # Handle format with period like "7.30PM"
      Regex.match?(~r/(\d{1,2})\.(\d{1,2})(?:\s*)([ap]m|PM|AM)/i, time_str) ->
        [_, hour, minutes, am_pm] = Regex.run(~r/(\d{1,2})\.(\d{1,2})(?:\s*)([ap]m|PM|AM)/i, time_str)
        hour_int = String.to_integer(hour)
        am_pm_lower = String.downcase(am_pm)
        is_pm = String.contains?(am_pm_lower, "p")

        hour_24 = cond do
          is_pm && hour_int < 12 -> hour_int + 12
          !is_pm && hour_int == 12 -> 0
          true -> hour_int
        end

        Logger.debug("⏰ Converted period format: #{hour_int}.#{minutes}#{am_pm} -> #{hour_24}:#{minutes}")
        "#{String.pad_leading("#{hour_24}", 2, "0")}:#{minutes}"

      # Handle format with colon like "8:30pm"
      Regex.match?(~r/(\d{1,2}):(\d{2})(?:\s*)([ap]m|PM|AM)/i, time_str) ->
        [_, hour, minutes, am_pm] = Regex.run(~r/(\d{1,2}):(\d{2})(?:\s*)([ap]m|PM|AM)/i, time_str)
        hour_int = String.to_integer(hour)
        am_pm_lower = String.downcase(am_pm)
        is_pm = String.contains?(am_pm_lower, "p")

        hour_24 = cond do
          is_pm && hour_int < 12 -> hour_int + 12
          !is_pm && hour_int == 12 -> 0
          true -> hour_int
        end

        Logger.debug("⏰ Converted colon format: #{hour_int}:#{minutes}#{am_pm} -> #{hour_24}:#{minutes}")
        "#{String.pad_leading("#{hour_24}", 2, "0")}:#{minutes}"

      # Handle format without minutes like "8pm"
      Regex.match?(~r/(\d{1,2})(?:\s*)([ap]m|PM|AM)/i, time_str) ->
        [_, hour, am_pm] = Regex.run(~r/(\d{1,2})(?:\s*)([ap]m|PM|AM)/i, time_str)
        hour_int = String.to_integer(hour)
        am_pm_lower = String.downcase(am_pm)
        is_pm = String.contains?(am_pm_lower, "p")

        hour_24 = cond do
          is_pm && hour_int < 12 -> hour_int + 12
          !is_pm && hour_int == 12 -> 0
          true -> hour_int
        end

        Logger.debug("⏰ Converted hour-only format: #{hour_int}#{am_pm} -> #{hour_24}:00")
        "#{String.pad_leading("#{hour_24}", 2, "0")}:00"

      true ->
        Logger.debug("⏰ Could not parse 12h time: '#{time_str}'")
        "00:00"
    end
  end

  # Try to extract date and time from the og:title metadata
  defp try_extract_from_og_title(document) do
    case Floki.find(document, "meta[property='og:title']") |> Floki.attribute("content") do
      [content | _] ->
        # Pattern like: "Next on Saturday 1 Mar"
        case Regex.run(~r/Next on ([A-Za-z]+) (\d+ [A-Za-z]+)/, content) do
          [_, day, date] -> {"00:00", day, date}
          _ -> {"00:00", "Unknown", "Unknown"}
        end
      _ -> {"00:00", "Unknown", "Unknown"}
    end
  end

  # Extract latitude from the document
  defp extract_latitude(document) do
    script_content = extract_script_content(document)
    case Regex.run(~r/lat:\s*(-?\d+\.\d+)/, script_content) do
      [_, lat] -> lat
      _ -> ""
    end
  end

  # Extract longitude from the document
  defp extract_longitude(document) do
    script_content = extract_script_content(document)
    case Regex.run(~r/lng:\s*(-?\d+\.\d+)/, script_content) do
      [_, lng] -> lng
      _ -> ""
    end
  end

  # Extract the JavaScript content containing lat/lng
  defp extract_script_content(document) do
    document
    |> Floki.find("script")
    |> Enum.map(&Floki.raw_html/1)
    |> Enum.find("", &String.contains?(&1, "createMarker"))
  end

  # Extract description from the document
  defp extract_description(document) do
    case Floki.find(document, "p.sm1") do
      [element | _] -> Floki.text(element)
      _ -> ""
    end
  end
end

defmodule TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.VenueDetailsExtractor do
  @moduledoc """
  Extracts additional venue details from individual venue pages.
  """

  require Logger

  # Fetches additional details about the venue from its details page with retries
  def extract_additional_details(nil), do: {:error, "No URL available"}
  def extract_additional_details(url) when is_binary(url), do: extract_additional_details(url, 0)

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

  # Extract venue ID from URL or document
  defp extract_venue_id(url, document) do
    # Try to extract from URL first
    case Regex.run(~r/\/venues\/(\d+)/, url) do
      [_, venue_id] ->
        Logger.debug("📌 Extracted venue ID from URL: #{venue_id}")
        venue_id
      nil ->
        # Try to find it in the document
        document
        |> Floki.find("body")
        |> Floki.attribute("data-venue-id")
        |> List.first()
        |> case do
          nil ->
            # Try alternate method - look for it in script tags
            scripts = Floki.find(document, "script")
            Enum.find_value(scripts, fn script ->
              script_text = Floki.text(script)
              case Regex.run(~r/venue[\"']?\s*:\s*[\"']?(\d+)[\"']?/, script_text) do
                [_, venue_id] -> venue_id
                nil -> nil
              end
            end)
          id -> id
        end
    end
  end

  # Extract performer from AJAX endpoint with retries
  defp extract_performer(nil), do: {:error, "No venue ID available"}
  defp extract_performer(venue_id), do: extract_performer(venue_id, 0)

  defp extract_performer(venue_id, retries) when retries < 3 do
    # Construct the API endpoint URL
    url = "https://www.geekswhodrink.com/wp-admin/admin-ajax.php?action=mb_display_venue_events&pag=1&venue=#{venue_id}&team=*"
    Logger.debug("🔍 Fetching performer data from: #{url} (attempt #{retries + 1}/3)")

    # Set a timeout to prevent hanging on slow requests
    options = [timeout: 5000, recv_timeout: 5000]

    case HTTPoison.get(url, [], options) do
      {:ok, %{status_code: 200, body: body}} ->
        process_performer_response(body)

      {:ok, %{status_code: status}} ->
        Logger.error("❌ Failed to fetch performer data. Status: #{status}")
        retry_or_fail(venue_id, retries, "HTTP #{status}")

      {:error, reason} ->
        Logger.error("❌ Failed to fetch performer data: #{inspect(reason)}")
        retry_or_fail(venue_id, retries, "HTTP request failed: #{inspect(reason)}")
    end
  end

  defp extract_performer(_venue_id, retries) do
    Logger.error("❌ Failed to fetch performer data after #{retries} attempts")
    {:error, "Max retries exceeded"}
  end

  defp retry_or_fail(venue_id, retries, _error_reason) do
    # Exponential backoff: wait longer between each retry
    backoff_ms = :math.pow(2, retries) * 500 |> round()
    Logger.info("⏱️ Retrying performer data fetch in #{backoff_ms}ms...")
    Process.sleep(backoff_ms)
    extract_performer(venue_id, retries + 1)
  end

  defp process_performer_response(body) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        # Look for quizmaster info in the quizzes__meta div
        meta_div = Floki.find(document, ".quizzes__meta")

        if Enum.empty?(meta_div) do
          Logger.debug("❌ No .quizzes__meta div found in performer response")
          {:error, "No quizmaster information found"}
        else
          # Extract name
          name = document
          |> Floki.find(".quiz__master p")
          |> Floki.text()
          |> String.trim()
          |> extract_name_from_text()
          |> truncate_name(200) # Truncate name to avoid database errors

          # Extract profile image
          profile_image = document
          |> Floki.find(".quiz__avatar img")
          |> Floki.attribute("src")
          |> List.first()

          # If we have an image but no name, provide a default name
          cond do
            is_nil(name) and is_nil(profile_image) ->
              {:error, "No performer name or image found"}
            is_nil(name) and not is_nil(profile_image) ->
              {:ok, %{name: "Geeks Who Drink Quizmaster", profile_image: profile_image}}
            true ->
              {:ok, %{name: name, profile_image: profile_image}}
          end
        end

      {:error, reason} ->
        Logger.error("❌ Failed to parse performer HTML: #{inspect(reason)}")
        {:error, "Failed to parse performer HTML"}
    end
  end

  defp extract_name_from_text(text) do
    case text do
      nil -> nil
      "" -> nil
      text ->
        # Clean up the text by removing repeated "Quizmaster:" prefixes
        clean_text = text
        |> String.replace(~r/Quizmaster:\s*/i, "Quizmaster: ", global: true)
        |> String.replace(~r/(Quizmaster:\s+){2,}/i, "Quizmaster: ", global: true)

        # Extract the name, typically in "With Quizmaster John Doe" format
        name = if String.contains?(clean_text, "Quizmaster") do
          clean_text
          |> String.replace(~r/.*Quizmaster:\s*/i, "")
          |> String.trim()
        else
          # If not in the expected format, just return the text
          clean_text |> String.trim()
        end

        # Ensure we don't return an empty string
        case name do
          "" -> "Unknown Quizmaster"
          name -> name
        end
    end
  end

  # Helper to truncate name to a maximum length
  defp truncate_name(nil, _), do: nil
  defp truncate_name(name, max_length) when is_binary(name) do
    if String.length(name) > max_length do
      Logger.warning("⚠️ Truncating performer name from #{String.length(name)} to #{max_length} characters")
      String.slice(name, 0, max_length)
    else
      name
    end
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

  defp extract_additional_details(url, retries) when retries < 3 do
    Logger.debug("🔍 Fetching additional venue details from: #{url} (attempt #{retries + 1}/3)")

    # Set appropriate timeouts and follow redirects
    options = [timeout: 10000, recv_timeout: 10000, follow_redirect: true]

    case HTTPoison.get(url, [], options) do
      {:ok, %{status_code: 200, body: body}} ->
        case Floki.parse_document(body) do
          {:ok, document} ->
            # Extract venue ID for performer API call
            venue_id = extract_venue_id(url, document)

            # Parse basic details from main document
            details = parse_details(document)

            # Add performer details if possible
            details =
              case extract_performer(venue_id) do
                {:ok, performer} ->
                  Logger.debug("✅ Found performer: #{inspect(performer)}")
                  Map.put(details, :performer, performer)
                {:error, reason} ->
                  Logger.debug("❌ No performer found: #{reason}")
                  details
              end

            {:ok, details}
          {:error, reason} ->
            Logger.error("❌ Failed to parse venue details HTML: #{inspect(reason)}")
            retry_or_fail_details(url, retries, "Failed to parse venue details HTML: #{inspect(reason)}")
        end

      {:ok, %{status_code: status}} ->
        Logger.error("❌ Failed to fetch venue details. Status: #{status}")
        retry_or_fail_details(url, retries, "HTTP #{status}")

      {:error, reason} ->
        Logger.error("❌ Failed to fetch venue details: #{inspect(reason)}")
        retry_or_fail_details(url, retries, "HTTP request failed: #{inspect(reason)}")
    end
  end

  defp extract_additional_details(_url, retries) do
    Logger.error("❌ Failed to fetch venue details after #{retries} attempts")
    {:error, "Max retries exceeded"}
  end

  defp retry_or_fail_details(url, retries, _error_reason) do
    # Exponential backoff: wait longer between each retry
    backoff_ms = :math.pow(2, retries) * 1000 |> round()
    Logger.info("⏱️ Retrying venue details fetch in #{backoff_ms}ms...")
    Process.sleep(backoff_ms)
    extract_additional_details(url, retries + 1)
  end
end

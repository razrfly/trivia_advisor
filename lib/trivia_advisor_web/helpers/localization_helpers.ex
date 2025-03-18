defmodule TriviaAdvisorWeb.Helpers.LocalizationHelpers do
  @moduledoc """
  Helper functions for handling localization of times, dates, and other values
  based on country data.
  """
  require Logger

  # Define our CLDR module for the project - dynamically including common locales
  # but not hardcoding specific countries
  defmodule TriviaAdvisor.Cldr do
    use Cldr,
      locales: ["en", "fr", "de", "es", "it", "ja", "zh", "ru", "pt", "nl", "en-GB", "pl"],
      default_locale: "en",
      providers: [Cldr.Number, Cldr.DateTime, Cldr.Calendar]
  end

  @doc """
  Formats time based on the country's locale preferences.
  Takes a time (Time struct or string) and a country object.

  ## Examples

      iex> format_localized_time(~T[19:30:00], %{code: "US"})
      "7:30 PM"

      iex> format_localized_time("7:30 PM", %{code: "GB"})
      "19:30"

  """
  def format_localized_time(time, country) do
    # Get locale from country data
    locale = get_locale_from_country(country)

    # Log for debugging
    Logger.debug("Formatting time #{inspect(time)} with locale: #{inspect(locale)}, country: #{inspect(country)}")

    # Convert to Time struct
    case normalize_time(time) do
      %Time{} = time_struct ->
        # Get appropriate time zone for the country if available
        timezone = get_country_timezone(country)

        # Create a DateTime with the country's timezone if available, or UTC as fallback
        datetime = case timezone do
          nil ->
            # Use UTC if no timezone available
            DateTime.new!(Date.utc_today(), time_struct, "Etc/UTC")
          tz ->
            # Use country's timezone - this ensures proper localization
            # We still use today's date as we're only concerned with time formatting
            DateTime.new!(Date.utc_today(), time_struct, tz)
        end

        # Log which timezone we're using
        Logger.debug("Using timezone: #{datetime.time_zone} for country: #{inspect(country)}")

        # Determine format based on country's time format preference
        format_options = if uses_24h_format?(country) do
          # 24-hour format
          [format: :time, style: :medium]
        else
          # 12-hour format
          [format: :time]
        end

        # Use CLDR with appropriate format
        result = TriviaAdvisor.Cldr.DateTime.to_string(datetime, format_options ++ [locale: locale])
        Logger.debug("CLDR formatting result: #{inspect(result)} with options: #{inspect(format_options)}")

        case result do
          {:ok, formatted} -> formatted
          _ ->
            # If CLDR failed, use fallback based on country preference
            if uses_24h_format?(country) do
              # 24-hour format fallback
              "#{String.pad_leading("#{time_struct.hour}", 2, "0")}:#{String.pad_leading("#{time_struct.minute}", 2, "0")}"
            else
              # 12-hour format fallback
              fallback_format(time_struct)
            end
        end

      _ ->
        "#{time}"
    end
  end

  # Determine if a country uses 24-hour time format
  # This uses the Countries library to get country info if available
  defp uses_24h_format?(country) do
    # Default for all of continental Europe, Asia, Africa, South America
    # Only a few countries (US, UK, Canada, Australia, etc.) use 12-hour format
    cond do
      is_nil(country) -> false
      !Map.has_key?(country, :code) -> false
      is_nil(country.code) -> false
      true ->
        country_code = country.code
        try do
          # Try to get countries data
          country_data = Countries.get(country_code)

          # Get region from countries data
          region = country_data.region
          continent = country_data.continent

          Logger.debug("Country #{country_code} is in region: #{inspect(region)}, continent: #{inspect(continent)}")

          # Most countries use 24h format except these primarily English-speaking ones
          !(country_code in ["US", "CA", "AU", "NZ", "PH"] ||
            (country_code == "GB") || # UK uses both but defaults to 12h in casual settings
            (region == "North America" && country_code != "MX"))
        rescue
          e ->
            Logger.debug("Error determining time format for #{inspect(country.code)}: #{inspect(e)}")
            # Default to 24h format for most countries except known 12h format countries
            !(country.code in ["US", "CA", "AU", "NZ", "GB", "PH"])
        end
    end
  end

  # Get locale from country data using Countries library
  defp get_locale_from_country(country) do
    cond do
      # First check if the country argument is nil
      is_nil(country) -> "en"

      # Check if we have a country code
      !Map.has_key?(country, :code) || is_nil(country.code) -> "en"

      # Otherwise use country code to determine locale
      true ->
        try do
          country_code = country.code
          Logger.debug("Determining locale for country code: #{country_code}")

          # Try to get country info from Countries library
          country_data = Countries.get(country_code)

          # Dynamic language code extraction from the Countries library data
          language_code =
            if country_data do
              # The official language is typically stored as a comma-separated string in languages_official
              official_languages =
                if Map.has_key?(country_data, :languages_official) && country_data.languages_official do
                  country_data.languages_official |> String.split(",") |> Enum.map(&String.trim/1)
                else
                  []
                end

              # Spoken languages as fallback
              spoken_languages =
                if Map.has_key?(country_data, :languages_spoken) && country_data.languages_spoken do
                  country_data.languages_spoken |> String.split(",") |> Enum.map(&String.trim/1)
                else
                  []
                end

              # Take the first available language (official preferred, then spoken)
              cond do
                length(official_languages) > 0 -> List.first(official_languages)
                length(spoken_languages) > 0 -> List.first(spoken_languages)
                # Some special cases where code doesn't match language code
                country_code == "GB" -> "en"
                country_code == "US" -> "en"
                true -> String.downcase(country_code) # Fallback to country code lowercase
              end
            else
              # If no country data, fallback to country code
              String.downcase(country_code)
            end

          Logger.debug("Found language code #{language_code} for country #{country_code}")

          # Construct locale
          case country_code do
            "GB" -> "en-GB"  # Special case for UK English
            _ ->
              # Check if our CLDR supports this specific locale
              specific_locale = "#{String.downcase(language_code)}-#{String.upcase(country_code)}"
              generic_locale = String.downcase(language_code)

              # Try specific locale first, then fall back to generic
              if specific_locale in TriviaAdvisor.Cldr.known_locale_names() do
                specific_locale
              else
                if generic_locale in TriviaAdvisor.Cldr.known_locale_names() do
                  generic_locale
                else
                  "en" # Ultimate fallback
                end
              end
          end

        rescue
          e ->
            Logger.debug("Error determining locale for #{inspect(country)}: #{inspect(e)}")
            # Simple fallback to "en" for all errors
            "en"
        end
    end
  end

  # Normalize different time formats to Time struct
  defp normalize_time(%Time{} = time), do: time

  defp normalize_time(time_str) when is_binary(time_str) do
    # Try to parse time string with AM/PM
    case Regex.run(~r/(\d{1,2}):?(\d{2})(?::(\d{2}))?\s*(AM|PM)?/i, time_str) do
      [_, hour, minute, _, am_pm] ->
        {hour_int, _} = Integer.parse(hour)
        {minute_int, _} = Integer.parse(minute)

        hour_24 = case String.upcase(am_pm || "") do
          "PM" when hour_int < 12 -> hour_int + 12
          "AM" when hour_int == 12 -> 0
          _ -> hour_int
        end

        case Time.new(hour_24, minute_int, 0) do
          {:ok, time} -> time
          _ -> nil
        end
      _ -> nil
    end
  end

  defp normalize_time(_), do: nil

  # Fallback format if CLDR fails
  defp fallback_format(%Time{} = time) do
    hour = time.hour
    am_pm = if hour >= 12, do: "PM", else: "AM"
    hour_12 = cond do
      hour == 0 -> 12
      hour > 12 -> hour - 12
      true -> hour
    end

    "#{hour_12}:#{String.pad_leading("#{time.minute}", 2, "0")} #{am_pm}"
  end

  # Get the most representative timezone for a country
  defp get_country_timezone(country) do
    if is_nil(country) || !Map.has_key?(country, :code) || is_nil(country.code) do
      nil
    else
      try do
        country_code = country.code
        # Get country data from Countries library
        country_data = Countries.get(country_code)

        if is_nil(country_data) do
          nil
        else
          # Try to infer timezone from country data
          cond do
            # Check for geo coordinate based approach - most common
            Map.has_key?(country_data, :geo) && is_map(country_data.geo) &&
              (Map.has_key?(country_data.geo, :latitude) || Map.has_key?(country_data.geo, :latitude_dec)) &&
              (Map.has_key?(country_data.geo, :longitude) || Map.has_key?(country_data.geo, :longitude_dec)) ->
              # Get longitude (prefer decimal version if available)
              long = cond do
                Map.has_key?(country_data.geo, :longitude_dec) && is_binary(country_data.geo.longitude_dec) ->
                  {val, _} = Float.parse(country_data.geo.longitude_dec)
                  val
                Map.has_key?(country_data.geo, :longitude) && is_number(country_data.geo.longitude) ->
                  country_data.geo.longitude
                true -> 0.0
              end

              # Map to standard timezone name based on rough longitude
              cond do
                long >= -10 && long <= 25 -> "Europe/London"
                long > 25 && long <= 45 -> "Europe/Athens"
                long > 45 && long <= 90 -> "Asia/Kolkata"
                long > 90 && long <= 135 -> "Asia/Shanghai"
                long > 135 && long <= 180 -> "Asia/Tokyo"
                long >= -45 && long < -10 -> "Atlantic/Azores"
                long >= -80 && long < -45 -> "America/New_York"
                long >= -120 && long < -80 -> "America/Chicago"
                long >= -165 && long < -120 -> "America/Los_Angeles"
                true -> "Etc/UTC"
              end

            # Check for region/continent based approach
            Map.has_key?(country_data, :region) && is_binary(country_data.region) ->
              # Map regions to timezones
              case country_data.region do
                "Europe" -> "Europe/London"
                "Asia" -> "Asia/Shanghai"
                "Africa" -> "Africa/Cairo"
                "South America" -> "America/Sao_Paulo"
                "North America" -> "America/New_York"
                "Oceania" -> "Australia/Sydney"
                _ -> "Etc/UTC"
              end

            true ->
              # Ultimate fallback - UTC
              "Etc/UTC"
          end
        end
      rescue
        e ->
          Logger.debug("Error determining timezone for #{inspect(country)}: #{inspect(e)}")
          "Etc/UTC"  # Default to UTC on errors
      end
    end
  end
end

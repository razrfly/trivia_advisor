defmodule TriviaAdvisorWeb.Helpers.LocalizationHelpers do
  @moduledoc """
  Helper functions for handling localization of times, dates, and other values
  based on country data.
  """

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

    # Special case: if time is a number-only string like "730", convert it to proper format
    time = if is_binary(time) do
      if Regex.match?(~r/^\d+$/, time) && String.length(time) >= 3 do
        # Convert numeric string like "730" to "7:30" format
        hours = String.slice(time, 0..-3//1)
        minutes = String.slice(time, -2..-1//1)
        "#{hours}:#{minutes}"
      else
        time
      end
    else
      time
    end

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

        # Determine format based on country's time format preference
        format_options = if uses_24h_format?(country) do
          # 24-hour format (use "Hm" format which is HH:mm)
          [format: "Hm"]
        else
          # 12-hour format (use "hm" format which is h:mm a)
          [format: "hm"]
        end

        # Use CLDR with appropriate format
        result = TriviaAdvisor.Cldr.DateTime.to_string(datetime, format_options ++ [locale: locale])

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
        # If we couldn't parse it as a time, but it's a numeric string, format it nicely
        if is_binary(time) do
          if Regex.match?(~r/^\d+$/, time) && String.length(time) >= 3 do
            hours = String.slice(time, 0..-3//1)
            minutes = String.slice(time, -2..-1//1)
            hour_int = String.to_integer(hours)

            # Format with AM/PM for countries using 12h format
            if uses_24h_format?(country) do
              "#{hours}:#{minutes}"
            else
              am_pm = if hour_int >= 12, do: "PM", else: "AM"
              hour_12 = cond do
                hour_int == 0 -> 12
                hour_int > 12 -> hour_int - 12
                true -> hour_int
              end
              "#{hour_12}:#{minutes} #{am_pm}"
            end
          else
            "#{time}"
          end
        else
          "#{time}"
        end
    end
  end

  # Determine if a country uses 24-hour time format based on geographical and cultural patterns
  # rather than hardcoded country lists
  defp uses_24h_format?(country) do
    cond do
      is_nil(country) -> false
      !Map.has_key?(country, :code) -> false
      is_nil(country.code) -> false
      true ->
        country_code = country.code
        try do
          # Try to get countries data
          country_data = Countries.get(country_code)

          # Most countries worldwide use 24h format
          # English-speaking nations and their cultural affiliates typically use 12h format
          # Let's determine this based on region and language rather than hardcoded lists
          cond do
            # If we can't get country data, use common knowledge that most countries use 24h
            is_nil(country_data) -> true

            # Check if the region is North America (mostly 12h except Mexico)
            Map.has_key?(country_data, :region) && country_data.region == "North America" ->
              # Mexico uses 24h format
              country_code == "MX"

            # Check if the main language is English (English-speaking countries prefer 12h format)
            is_language_primary?(country_data, "en") -> false

            # Check if it's a commonwealth or English-influenced country (many use 12h in daily life)
            # Commonwealth countries often use both formats but 12h is common in daily life
            Map.has_key?(country_data, :commonwealth) && country_data.commonwealth -> false

            # Default: Most other countries worldwide use 24h format
            true -> true
          end
        rescue
          _e ->
            # Default to 24h format if we can't determine - majority of world uses it
            true
        end
    end
  end

  # Helper to check if a particular language is the primary language for a country
  defp is_language_primary?(country_data, language_code) do
    cond do
      # Check official languages first
      Map.has_key?(country_data, :languages_official) && is_binary(country_data.languages_official) ->
        primary_lang = country_data.languages_official
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> List.first()
          |> String.downcase()

        primary_lang == language_code

      # Then check spoken languages
      Map.has_key?(country_data, :languages_spoken) && is_binary(country_data.languages_spoken) ->
        primary_lang = country_data.languages_spoken
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> List.first()
          |> String.downcase()

        primary_lang == language_code

      # If we can't determine, return false
      true -> false
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
          _e ->
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

  # Get timezone information from the country using the Countries library
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
          # Look for timezone in country_data
          # Most country libraries store timezone info in different ways:
          # The Countries library stores this info in the timezone field
          cond do
            # If there's a direct timezone field, use it
            Map.has_key?(country_data, :timezone) && !is_nil(country_data.timezone) ->
              country_data.timezone

            # Some implementations use a timezones field with a list
            Map.has_key?(country_data, :timezones) && is_list(country_data.timezones) && length(country_data.timezones) > 0 ->
              # Get the first timezone name
              timezone = List.first(country_data.timezones)
              if is_binary(timezone), do: timezone, else: nil

            # Try to construct from country's capital city if available - many timezones follow this pattern
            Map.has_key?(country_data, :capital) && !is_nil(country_data.capital) &&
            Map.has_key?(country_data, :continent) && !is_nil(country_data.continent) ->
              "#{country_data.continent}/#{country_data.capital}" |> String.replace(" ", "_")

            # If all else fails, return nil and let the caller use a UTC default
            true -> nil
          end
        end
      rescue
        _e ->
          nil  # Let the caller use the default
      end
    end
  end
end

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
      locales: ["en", "fr", "de", "es", "it", "ja", "zh", "ru", "pt", "nl", "en-GB"],
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
        # Format with today's date to create a DateTime for formatting
        datetime = DateTime.new!(Date.utc_today(), time_struct, "Etc/UTC")

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

          # Use official language as locale base
          languages = country_data.languages || []
          official_language =
            languages
            |> Enum.find(fn lang -> lang.official end)
            |> case do
              nil -> List.first(languages) # If no official language, use first
              lang -> lang
            end

          language_code = if official_language do
            official_language.iso_639_1 || "en"
          else
            "en"
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
            # Simple fallback based on common language-country pairs
            # This is only used if the Countries library fails
            case country.code do
              "GB" -> "en-GB"
              "US" -> "en"
              "FR" -> "fr"
              "DE" -> "de"
              "ES" -> "es"
              "IT" -> "it"
              "JP" -> "ja"
              "CN" -> "zh"
              "RU" -> "ru"
              "PT" -> "pt"
              "NL" -> "nl"
              "PL" -> "pl"
              _ -> "en"
            end
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
end

defmodule TriviaAdvisorWeb.Helpers.LocalizationHelpers do
  @moduledoc """
  Helper functions for handling localization of times, dates, and other values
  based on country data.
  """
  require Logger

  # Define our CLDR module for the project
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
      "7:30 PM (local time)"

      iex> format_localized_time("7:30 PM", %{code: "GB"})
      "19:30 (local time)"

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

        # Use different format options based on locale
        format_options = if locale in ["fr", "de", "es", "it", "ru", "pt", "nl", "zh", "ja"] do
          # Use 24-hour format for these locales
          [format: :time, style: :medium]
        else
          # Use default format for other locales (like en, en-GB which have their own conventions)
          [format: :time]
        end

        # Use CLDR with the locale from country data and appropriate format
        result = TriviaAdvisor.Cldr.DateTime.to_string(datetime, format_options ++ [locale: locale])
        Logger.debug("CLDR formatting result: #{inspect(result)} with options: #{inspect(format_options)}")

        case result do
          {:ok, formatted} -> formatted
          _ ->
            # If CLDR failed, use locale-specific fallback
            if locale in ["fr", "de", "es", "it", "ru", "pt", "nl", "zh", "ja"] do
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

  # Get locale from country data without hardcoding
  defp get_locale_from_country(country) do
    result = cond do
      # First check if the country argument is nil
      is_nil(country) -> "en"

      # Then check if country has a locale field (might be added in the future)
      Map.has_key?(country, :locale) && country.locale ->
        country.locale

      # Then if we have both language_code and country code, construct a locale
      Map.has_key?(country, :language_code) &&
      country.language_code &&
      Map.has_key?(country, :code) &&
      country.code ->
        "#{String.downcase(country.language_code)}-#{String.upcase(country.code)}"

      # Then try the code field for specific countries that need special handling
      Map.has_key?(country, :code) && country.code ->
        code = country.code
        Logger.debug("Getting locale for country code: #{inspect(code)}")

        case code do
          "FR" ->
            Logger.debug("French venue detected, using fr locale")
            "fr"
          "GB" -> "en-GB"
          "US" -> "en"  # Use standard English for US
          code when code in ["AU", "CA", "NZ"] -> "en"
          "DE" -> "de"
          "ES" -> "es"
          "IT" -> "it"
          "JP" -> "ja"
          "CN" -> "zh"
          "RU" -> "ru"
          "PT" -> "pt"
          "NL" -> "nl"
          _ ->
            Logger.debug("Defaulting to en for country code: #{inspect(code)}")
            "en" # Default to English for other countries
        end

      # Ultimate fallback
      true ->
        Logger.debug("Using ultimate fallback locale: en")
        "en"
    end

    Logger.debug("Determined locale: #{inspect(result)} for country: #{inspect(country)}")
    result
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

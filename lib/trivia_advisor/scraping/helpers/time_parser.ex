defmodule TriviaAdvisor.Scraping.Helpers.TimeParser do
  @moduledoc """
  Shared time parsing functionality for all scrapers.
  Handles various time formats and day of week parsing.
  """

  require Logger

  @default_time "20:00"

  @doc """
  Parses time text into standardized format.
  Returns {:ok, map} with day_of_week, start_time, and frequency.

  ## Examples

      iex> parse_time_text("Tuesdays, 6.30pm")
      {:ok, %{day_of_week: 2, start_time: "18:30", frequency: :weekly}}

      iex> parse_time_text("Every Thursday at 8pm")
      {:ok, %{day_of_week: 4, start_time: "20:00", frequency: :weekly}}
  """
  def parse_time_text(time_text) when is_binary(time_text) do
    # Normalize text
    normalized = time_text
    |> String.downcase()
    |> String.replace(~r/every\s+/, "")
    |> String.replace(~r/at\s+/, "")
    |> String.replace(",", "")
    |> String.split(~r/\(.*\)|\n|book:.*$/i) # Remove anything in parentheses, newlines, or after "Book:"
    |> List.first()
    |> String.trim()

    with {:ok, day} <- parse_day_of_week(normalized),
         {:ok, time} <- parse_time(normalized) do
      {:ok, %{
        day_of_week: day,
        start_time: time,
        frequency: :weekly
      }}
    else
      {:error, _} = error when not is_nil(time_text) ->
        # If we can parse the day but not the time, use default time
        case parse_day_of_week(normalized) do
          {:ok, day} ->
            {:ok, %{
              day_of_week: day,
              start_time: @default_time,
              frequency: :weekly
            }}
          _ -> error
        end
      error -> error
    end
  end

  def parse_time_text(nil), do: {:error, "Time text is nil"}

  @doc """
  Parses day of week from time text into integer (1-7, Monday-Sunday).
  Returns {:ok, integer} or {:error, reason}.
  """
  def parse_day_of_week(text) when is_binary(text) do
    # Match both "Monday" and "Mondays" patterns
    day_pattern = ~r/(?:every\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\b/i

    case Regex.run(day_pattern, text) do
      [_, day] ->
        day = String.downcase(day)
        {:ok, case day do
          "monday" -> 1
          "tuesday" -> 2
          "wednesday" -> 3
          "thursday" -> 4
          "friday" -> 5
          "saturday" -> 6
          "sunday" -> 7
        end}
      _ -> {:error, "Could not parse day from: #{text}"}
    end
  end

  def parse_day_of_week(nil), do: {:error, "Time text is nil"}

  @doc """
  Parses time string into 24-hour format.
  Returns {:ok, "HH:MM"} or {:error, reason}.

  ## Examples

      iex> parse_time("7.30pm")
      {:ok, "19:30"}

      iex> parse_time("8pm")
      {:ok, "20:00"}
  """
  def parse_time(text) when is_binary(text) do
    cond do
      # Match "7.30pm" or "7:30pm"
      result = Regex.run(~r/(\d{1,2})[:\.](\d{2})\s*(am|pm)/, text) ->
        [_, hour, minutes, period] = result
        convert_to_24h(hour, minutes, period)

      # Match "7pm"
      result = Regex.run(~r/(\d{1,2})\s*(am|pm)/, text) ->
        [_, hour, period] = result
        convert_to_24h(hour, "00", period)

      # Match "19:30" or "19.30"
      result = Regex.run(~r/(\d{2})[:\.](\d{2})/, text) ->
        [_, hour, minutes] = result
        with {h, ""} <- Integer.parse(hour),
             {m, ""} <- Integer.parse(minutes),
             true <- h in 0..23 and m in 0..59 do
          {:ok, :io_lib.format("~2..0B:~2..0B", [h, m]) |> to_string()}
        else
          _ -> {:error, "Invalid 24h time format"}
        end

      true ->
        {:error, "Could not parse time from: #{text}"}
    end
  end

  def parse_time(nil), do: {:error, "Time text is nil"}

  # Private helpers

  defp convert_to_24h(hour, minutes, period) when is_binary(hour) and is_binary(minutes) do
    with {h, ""} <- Integer.parse(hour),
         {m, ""} <- Integer.parse(minutes),
         true <- h in 1..12 and m in 0..59 do

      hour_24 = case {h, period} do
        {12, "am"} -> 0
        {12, "pm"} -> 12
        {h, "am"} -> h
        {h, "pm"} -> h + 12
      end

      {:ok, :io_lib.format("~2..0B:~2..0B", [hour_24, m]) |> to_string()}
    else
      _ -> {:error, "Invalid hour or minutes"}
    end
  end
end

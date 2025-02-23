defmodule TriviaAdvisor.Scraping.Scrapers.Inquizition.TimeParser do
  @moduledoc """
  Parses time text from Inquizition format into standardized format.
  """

  @doc """
  Parses time text like "Tuesdays, 6.30pm" into standardized format.

  Returns a map with:
  - day_of_week: 1-7 (Monday = 1)
  - start_time: "18:30"
  - frequency: :weekly

  ## Examples

      iex> parse_time("Tuesdays, 6.30pm")
      {:ok, %{day_of_week: 2, start_time: "18:30", frequency: :weekly}}

      iex> parse_time("Every Thursday at 8pm")
      {:ok, %{day_of_week: 4, start_time: "20:00", frequency: :weekly}}
  """
  def parse_time(time_text) when is_binary(time_text) do
    # Normalize text
    normalized = time_text
    |> String.downcase()
    |> String.replace(~r/every\s+/, "")
    |> String.replace(~r/at\s+/, "")
    |> String.replace(",", "")
    |> String.split(~r/\(.*\)|\n|book:.*$/i) # Remove anything in parentheses, newlines, or after "Book:"
    |> List.first()
    |> String.trim()

    with {:ok, day} <- parse_day(normalized),
         {:ok, time} <- parse_time_part(normalized) do
      {:ok, %{
        day_of_week: day,
        start_time: time,
        frequency: :weekly
      }}
    else
      error -> {:error, "Invalid time format: #{time_text} (#{inspect(error)})"}
    end
  end

  def parse_time(nil), do: {:error, "Time text is nil"}

  defp parse_day(text) do
    case Regex.run(~r/(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?/, text) do
      [_, "monday"] -> {:ok, 1}
      [_, "tuesday"] -> {:ok, 2}
      [_, "wednesday"] -> {:ok, 3}
      [_, "thursday"] -> {:ok, 4}
      [_, "friday"] -> {:ok, 5}
      [_, "saturday"] -> {:ok, 6}
      [_, "sunday"] -> {:ok, 7}
      _ -> {:error, "Could not parse day from: #{text}"}
    end
  end

  defp parse_time_part(text) do
    cond do
      # Match "7.30pm" or "7:30pm"
      result = Regex.run(~r/(\d{1,2})[:\.](\d{2})\s*(am|pm)/, text) ->
        [_, hour, minutes, period] = result
        convert_to_24h(hour, minutes, period)

      # Match "7pm"
      result = Regex.run(~r/(\d{1,2})\s*(am|pm)/, text) ->
        [_, hour, period] = result
        convert_to_24h(hour, "00", period)

      true ->
        {:error, "Could not parse time from: #{text}"}
    end
  end

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

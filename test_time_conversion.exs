require Logger

# Test time conversion from UTC to local time
test_times = [
  {"2022-09-23T01:00:00+0000", "7:00 pm"},  # 1:00 UTC -> 7:00 PM Mountain Time
  {"2022-09-23T02:00:00+0000", "8:00 pm"},  # 2:00 UTC -> 8:00 PM Mountain Time
  {"2022-09-23T00:00:00+0000", "6:00 pm"}   # 0:00 UTC -> 6:00 PM Mountain Time
]

Logger.configure(level: :debug)

IO.puts("\n⏰ TESTING TIME CONVERSION:")

Enum.each(test_times, fn {utc_time, expected_local} ->
  IO.puts("\nTesting conversion of #{utc_time} (expected: #{expected_local})")

  case DateTime.from_iso8601(utc_time) do
    {:ok, datetime, _} ->
      # Convert UTC time to local time (assuming US Mountain Time, UTC-6)
      local_hour = rem(datetime.hour + 18, 24)  # UTC to Mountain Time (UTC-6)
      minute = datetime.minute
      formatted_time = :io_lib.format("~2..0B:~2..0B", [local_hour, minute]) |> to_string()

      # Format for display
      period = if local_hour >= 12, do: "pm", else: "am"
      display_hour = case local_hour do
        0 -> 12
        h when h > 12 -> h - 12
        h -> h
      end
      display_time = "#{display_hour}:#{:io_lib.format("~2..0B", [minute]) |> to_string()} #{period}"

      IO.puts("UTC time: #{datetime.hour}:#{:io_lib.format("~2..0B", [minute]) |> to_string()}")
      IO.puts("Local time (24h): #{formatted_time}")
      IO.puts("Local time (12h): #{display_time}")
      IO.puts("Expected: #{expected_local}")
      IO.puts("Result: #{if display_time == expected_local, do: "✅ MATCH", else: "❌ MISMATCH"}")

    error ->
      IO.puts("Error parsing time: #{inspect(error)}")
  end
end)

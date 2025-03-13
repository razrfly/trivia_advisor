html = """
<div class="venueHero__time">
  <span>Thursdays at </span>
  <span class="time-moment" data-time="2022-09-23T01:00:00+0000">7:00 pm</span>
</div>
"""

defmodule TestExtraction do
  def extract_start_time_verbose(document) do
    IO.puts("\nDEBUG EXTRACTION:")
    # Step 1: Find the time-moment span
    span = Floki.find(document, ".venueHero__time .time-moment")
    IO.puts("Found span: #{inspect(span)}")

    # Step 2: Get visible text
    visible_time = Floki.text(span) |> String.trim()
    IO.puts("Visible time: #{inspect(visible_time)}")

    # Step 3: Get data-time attribute
    data_time = Floki.attribute(span, "data-time") |> List.first()
    IO.puts("Data-time attribute: #{inspect(data_time)}")

    # Now perform the actual extraction logic
    if visible_time && visible_time != "" do
      IO.puts("\nAttempting to parse visible time: #{visible_time}")
      # Try to convert 12-hour time (7:00 pm) to 24-hour time (19:00)
      case Regex.run(~r/(\d+):(\d+)\s*(am|pm)/i, visible_time) do
        [_, hour_str, minute_str, period] ->
          IO.puts("Regex matched: hour=#{hour_str}, minute=#{minute_str}, period=#{period}")
          hour = String.to_integer(hour_str)
          minute = String.to_integer(minute_str)

          hour = case String.downcase(period) do
            "pm" when hour < 12 ->
              new_hour = hour + 12
              IO.puts("Converting PM time: #{hour} -> #{new_hour}")
              new_hour
            "am" when hour == 12 ->
              IO.puts("Converting 12 AM to 0")
              0
            _ ->
              IO.puts("Keeping hour as is: #{hour}")
              hour
          end

          # Format as HH:MM
          formatted_time = :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> to_string()
          IO.puts("Final formatted time: #{formatted_time}")
          formatted_time
        result ->
          IO.puts("Regex failed with result: #{inspect(result)}")
          "20:00"  # Default fallback for testing
      end
    else
      IO.puts("No visible time found, falling back to data-time")
      "20:00"  # Default fallback for testing
    end
  end
end

# Parse the HTML
document = Floki.parse_document!(html)

# Test the extraction
result = TestExtraction.extract_start_time_verbose(document)
IO.puts("\nFINAL RESULT: #{result}")

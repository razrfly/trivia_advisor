# Test script for time formatting functions
# Run with: mix run lib/debug/test_time_ago.exs

# Import the FormatHelpers module
alias TriviaAdvisorWeb.Helpers.FormatHelpers
require Logger

IO.puts("Testing time formatter functions...")

# System information
system_date = DateTime.utc_now()
IO.puts("System date: #{DateTime.to_string(system_date)}")

# Test time_ago function
specific_date = ~N[2024-04-10 12:00:00]
IO.puts("\nTesting time_ago:")
IO.puts("Specific date: #{NaiveDateTime.to_string(specific_date)}")
IO.puts("Formatted: #{FormatHelpers.time_ago(specific_date)}")

# Test format_month_day function
test_date = ~D[2023-01-15]
IO.puts("\nTesting format_month_day:")
IO.puts("Test date: #{Date.to_string(test_date)}")
IO.puts("Formatted: #{FormatHelpers.format_month_day(test_date)}")

# Test format_day_of_week function
IO.puts("\nTesting format_day_of_week:")
for day <- 1..7 do
  formatted = FormatHelpers.format_day_of_week(day)
  IO.puts("Day #{day}: #{formatted}")
end

# Test titleize function
IO.puts("\nTesting titleize:")
test_strings = ["hello world", "john doe", "the QUICK brown FOX", "  multiple   spaces  "]
for string <- test_strings do
  IO.puts("Original: '#{string}'")
  IO.puts("Titleized: '#{FormatHelpers.titleize(string)}'")
end

# Test time_ago with current Timex implementation
IO.puts("\nTimex format test:")
case Timex.format(specific_date, "{relative}", :relative) do
  {:ok, relative_time} -> IO.puts("Timex format result: #{relative_time}")
  {:error, reason} -> IO.puts("Timex format error: #{inspect(reason)}")
end

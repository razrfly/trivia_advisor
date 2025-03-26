# Run a full job with force_refresh_images=true to verify our fixes work
# This is the final test to confirm that we've properly fixed the issue

require Logger
alias TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Scraping.Source

IO.puts("\n===== FULL JOB TEST WITH FORCE_REFRESH_IMAGES=TRUE =====")
IO.puts("This test runs a real QuizmeistersDetailJob with force_refresh_images=true")
IO.puts("and checks if our fixes work in the full system.\n")

# Get source
source = Repo.get_by(Source, name: "quizmeisters")
if is_nil(source) do
  IO.puts("ERROR: Source 'quizmeisters' not found")
  System.halt(1)
end

# Create venue data for test
venue_data = %{
  "name" => "10 Toes Buderim",
  "phone" => "07 5373 5003",
  "address" => "15/3 Pittards Rd, Buderim, Queensland, 4556, AU",
  "url" => "https://www.quizmeisters.com/venues/qld-10-toes",
  "postcode" => "4556",
  "latitude" => "-26.6630807",
  "longitude" => "153.0518295"
}

IO.puts("\n➡️ Creating job with force_refresh_images=true")
args = %{
  "venue" => venue_data,
  "source_id" => source.id,
  "force_refresh_images" => true
}

# Create job struct
job = %Oban.Job{
  id: 999999,
  queue: "test_queue",
  worker: "TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob",
  args: args,
  state: "available",
  inserted_at: DateTime.utc_now(),
  scheduled_at: DateTime.utc_now(),
  attempted_at: nil,
  completed_at: nil,
  attempted_by: nil,
  discarded_at: nil,
  priority: 0,
  tags: ["test"],
  errors: [],
  max_attempts: 3
}

# Change logger level to see only important logs
Logger.configure(level: :info)

# Define a regex for log lines we want to highlight
force_refresh_regex = ~r/(force_refresh.*?=|Process dictionary force_refresh_images)/

# Define a function to colorize log messages
colorize_log = fn message ->
  # Don't colorize non-string messages
  if is_binary(message) do
    # Colorize based on whether force_refresh=true or false is present
    cond do
      String.contains?(message, ["force_refresh=true", "force_refresh: true", "force_refresh_images = true"]) ->
        # Green for true values
        IO.ANSI.green() <> message <> IO.ANSI.reset()

      String.contains?(message, ["force_refresh=false", "force_refresh: false", "force_refresh_images = false"]) ->
        # Red for false values
        IO.ANSI.red() <> message <> IO.ANSI.reset()

      String.match?(message, force_refresh_regex) ->
        # Yellow for mentions without clear values
        IO.ANSI.yellow() <> message <> IO.ANSI.reset()

      true ->
        message
    end
  else
    message
  end
end

# Create a custom logger backend that colorizes output
defmodule ColorLogger do
  def init(_) do
    {:ok, %{}}
  end

  def handle_event({level, _gl, {Logger, message, timestamp, metadata}}, state) do
    # Format timestamp
    {{year, month, day}, {hour, minute, second, _millisecond}} = timestamp
    formatted_time = "#{year}-#{month}-#{day} #{hour}:#{minute}:#{second}"

    # Format log level
    level_str = case level do
      :info -> "[INFO]"
      :warn -> "[WARN]"
      :error -> "[ERROR]"
      :debug -> "[DEBUG]"
      _ -> "[#{level}]"
    end

    # Apply colorization
    colored_message = colorize_log.(to_string(message))

    # Print the formatted log
    IO.puts("#{formatted_time} #{level_str} #{colored_message}")

    {:ok, state}
  end
end

# Add the custom logger backend
:logger.add_handler(:color_logger, :logger_std_h, %{level: :info, filter_default: :log, formatter: {ColorLogger, :format}})

IO.puts("\n⏱️ Running job (will take ~30 seconds)...")
IO.puts("🔍 Watch for colored force_refresh logs (green=true, red=false)\n")

result = QuizmeistersDetailJob.perform(job)

IO.puts("\n===== JOB COMPLETED =====")
IO.puts("Result: #{inspect(result)}")

IO.puts("\n===== CONCLUSION =====")
IO.puts("Check that:")
IO.puts("1. All force_refresh values are TRUE (green)")
IO.puts("2. Both performer image and hero image were downloaded with force_refresh=true")
IO.puts("3. No errors were encountered in the process")
IO.puts("4. There are lines showing 'Force refreshing existing image' and 'Deleted existing image to force refresh'")

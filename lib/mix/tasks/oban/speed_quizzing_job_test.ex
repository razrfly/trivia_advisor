defmodule Mix.Tasks.Oban.SpeedQuizzingJobTest do
  use Mix.Task

  @shortdoc "Tests the SpeedQuizzing Index Job with a limited number of events"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Default to 5 events, but allow overriding with --limit=N argument
    limit = get_limit_from_args(args)

    IO.puts("🧪 Running SpeedQuizzing Index Job TEST with limit of #{limit} events...")

    # Call the index job but pass a limit option
    case TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob.perform(%Oban.Job{args: %{"limit" => limit}}) do
      {:ok, result} ->
        IO.puts("✅ Test completed successfully!")
        IO.puts("📊 Found #{result.event_count} events total")
        IO.puts("📊 Enqueued #{result.enqueued_jobs} detail jobs (limited to #{limit})")
        :ok

      {:error, reason} ->
        IO.puts("❌ Test failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # Extract limit from command line arguments
  defp get_limit_from_args(args) do
    limit_arg = Enum.find(args, fn arg -> String.starts_with?(arg, "--limit=") end)

    if limit_arg do
      limit_arg
      |> String.replace("--limit=", "")
      |> String.trim()
      |> String.to_integer()
    else
      5 # Default limit
    end
  end
end

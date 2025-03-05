defmodule Mix.Tasks.Oban.InquizitionJobTest do
  use Mix.Task

  @shortdoc "Tests the Inquizition Index Job with a limited number of venues"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Default to 3 venues, but allow overriding with --limit=N argument
    limit = get_limit_from_args(args)

    IO.puts("🧪 Running Inquizition Index Job TEST with limit of #{limit} venues...")

    # Call the index job but pass a limit option
    result = TriviaAdvisor.Scraping.Oban.InquizitionIndexJob.perform(%Oban.Job{args: %{"limit" => limit}})

    case result do
      {:ok, data} ->
        IO.puts("\n✅ Test completed successfully!")
        IO.puts("📊 Found #{data.venue_count} venues total")
        IO.puts("📊 Enqueued #{data.enqueued_jobs} detail jobs (limited to #{limit})")
        :ok

      other ->
        IO.puts("\n❌ Test failed: #{inspect(other)}")
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
      3 # Default limit
    end
  end
end

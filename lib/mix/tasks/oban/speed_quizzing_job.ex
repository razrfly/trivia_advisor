defmodule Mix.Tasks.Oban.SpeedQuizzingJob do
  use Mix.Task

  @shortdoc "Enqueues the SpeedQuizzingIndexJob in Oban or runs it immediately"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    if "--run-now" in args do
      # Run the job directly, bypassing Oban
      IO.puts("🔄 Running SpeedQuizzingIndexJob immediately...")

      case TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob.perform(%Oban.Job{args: %{}}) do
        {:ok, result} ->
          IO.puts("✅ Job completed successfully!")
          IO.puts("📊 Found #{result.event_count} events from SpeedQuizzing")

        {:error, reason} ->
          IO.puts("❌ Job failed: #{inspect(reason)}")
          exit({:shutdown, 1})
      end
    else
      # Enqueue the job in Oban
      IO.puts("📥 Enqueuing SpeedQuizzingIndexJob...")

      case TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob.new(%{}) |> Oban.insert() do
        {:ok, job} ->
          IO.puts("✅ Job enqueued successfully!")
          IO.puts("📌 Job ID: #{job.id}")
          IO.puts("⏱️ Scheduled at: #{job.scheduled_at}")

        {:error, changeset} ->
          IO.puts("❌ Failed to enqueue job:")
          IO.inspect(changeset.errors, label: "Errors")
          exit({:shutdown, 1})
      end
    end
  end
end

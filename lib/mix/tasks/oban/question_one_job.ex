defmodule Mix.Tasks.Oban.QuestionOneJob do
  use Mix.Task

  @shortdoc "Enqueues the QuestionOneIndexJob in Oban or runs it immediately"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    if "--run-now" in args do
      # Run the job directly, bypassing Oban
      IO.puts("🔄 Running QuestionOneIndexJob immediately...")

      case TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob.perform(%Oban.Job{args: %{}}) do
        {:ok, result} ->
          IO.puts("✅ Job completed successfully!")
          IO.puts("📊 Found #{result.venue_count} venues from Question One")
          IO.puts("📊 Enqueued #{result.enqueued_jobs} detail jobs")

        {:error, reason} ->
          IO.puts("❌ Job failed: #{inspect(reason)}")
          exit({:shutdown, 1})
      end
    else
      # Enqueue the job in Oban
      IO.puts("📥 Enqueuing QuestionOneIndexJob...")

      case TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob.new(%{}) |> Oban.insert() do
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

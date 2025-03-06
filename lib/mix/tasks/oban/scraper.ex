defmodule Mix.Tasks.Oban.Scraper do
  use Mix.Task

  @shortdoc "Enqueues or runs a scraper's IndexJob in Oban"

  @scrapers %{
    "speed_quizzing" => %{
      job_module: TriviaAdvisor.Scraping.Oban.SpeedQuizzingIndexJob,
      description: "SpeedQuizzing",
      result_key: :event_count
    },
    "question_one" => %{
      job_module: TriviaAdvisor.Scraping.Oban.QuestionOneIndexJob,
      description: "Question One",
      result_key: :venue_count
    },
    "inquizition" => %{
      job_module: TriviaAdvisor.Scraping.Oban.InquizitionIndexJob,
      description: "Inquizition",
      result_key: :venue_count
    },
    "quizmeisters" => %{
      job_module: TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob,
      description: "Quizmeisters",
      result_key: :venue_count
    }
  }

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    case args do
      [scraper_name | rest_args] ->
        case Map.get(@scrapers, scraper_name) do
          nil ->
            IO.puts("❌ Invalid scraper name: #{scraper_name}")
            IO.puts("Available scrapers: #{Enum.join(Map.keys(@scrapers), ", ")}")
            exit({:shutdown, 1})

          %{job_module: job_module, description: description, result_key: result_key} ->
            if "--run-now" in rest_args do
              run_now(job_module, description, result_key)
            else
              enqueue(job_module, description)
            end
        end

      _ ->
        IO.puts("❌ No scraper name provided.")
        IO.puts("Usage: mix oban.scraper [scraper_name] [--run-now]")
        IO.puts("Available scrapers: #{Enum.join(Map.keys(@scrapers), ", ")}")
        exit({:shutdown, 1})
    end
  end

  defp run_now(job_module, description, result_key) do
    IO.puts("🔄 Running #{description} IndexJob immediately...")

    case job_module.perform(%Oban.Job{args: %{}}) do
      {:ok, result} ->
        IO.puts("✅ Job completed successfully!")
        count = Map.get(result, result_key, 0)
        IO.puts("📊 Found #{count} records from #{description}")

        # If we have enqueued jobs info, display it
        if Map.has_key?(result, :enqueued_jobs) do
          IO.puts("📥 Enqueued #{result.enqueued_jobs} detail jobs")
        end

        :ok

      {:error, reason} ->
        IO.puts("❌ Job failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp enqueue(job_module, description) do
    IO.puts("📥 Enqueuing #{description} IndexJob...")

    case job_module.new(%{}) |> Oban.insert() do
      {:ok, job} ->
        IO.puts("✅ Job enqueued successfully!")
        IO.puts("📌 Job ID: #{job.id}")
        IO.puts("⏱️ Scheduled at: #{job.scheduled_at}")
        :ok

      {:error, changeset} ->
        IO.puts("❌ Failed to enqueue job:")
        IO.inspect(changeset.errors, label: "Errors")
        exit({:shutdown, 1})
    end
  end
end

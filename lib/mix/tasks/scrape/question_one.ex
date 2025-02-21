defmodule Mix.Tasks.Scrape.QuestionOne do
  use Mix.Task
  require Logger

  @shortdoc "Runs the QuestionOne scraper via Oban"

  def run(_) do
    # Start the application and its dependencies
    Mix.Task.run("app.start")

    # Load .env file if it exists
    if File.exists?(".env") do
      DotenvParser.load_file(".env")
      Logger.info("📝 Loaded .env file")
    end

    # Verify API key is available
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 ->
        Logger.info("🔑 API key loaded successfully")
        enqueue_and_await_job()

      _ ->
        Logger.error("❌ GOOGLE_MAPS_API_KEY not found in environment")
        System.halt(1)
    end
  end

  defp enqueue_and_await_job do
    case %{} |> TriviaAdvisor.Scraping.Jobs.QuestionOneJob.new() |> Oban.insert() do
      {:ok, job} ->
        Logger.info("✅ Successfully enqueued scraping job")

        # Keep checking until job completes or fails
        case wait_for_completion(job.id) do
          :completed -> Logger.info("✅ Scraping job completed successfully")
          :failed -> Logger.error("❌ Scraping job failed")
        end

      {:error, error} ->
        Logger.error("❌ Failed to enqueue job: #{inspect(error)}")
        System.halt(1)
    end
  end

  defp wait_for_completion(job_id, attempts \\ 0) do
    if attempts < 60 do # Wait up to 5 minutes
      # Query the job's current state
      case TriviaAdvisor.Repo.get(Oban.Job, job_id) do
        %{state: "completed"} -> :completed
        %{state: "discarded"} -> :failed
        %{state: "cancelled"} -> :failed
        nil -> :failed
        _ ->
          Process.sleep(5000) # Wait 5 seconds between checks
          wait_for_completion(job_id, attempts + 1)
      end
    else
      Logger.error("❌ Job timed out")
      :failed
    end
  end
end

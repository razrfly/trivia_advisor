defmodule TriviaAdvisor.Scraping.Oban.FuzzyDuplicateProcessingJob do
  @moduledoc """
  Oban job for processing fuzzy duplicates in the background.
  This job can handle the long-running fuzzy duplicate processing without timeout issues.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias TriviaAdvisor.Services.FuzzyDuplicateProcessor

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    Logger.info("🚀 FuzzyDuplicateProcessingJob STARTED - Job ID: #{job.id}")

    try do
      Logger.info("🔍 Checking FuzzyDuplicateProcessor module availability...")

      # Verify module exists
      unless Code.ensure_loaded?(FuzzyDuplicateProcessor) do
        error_msg = "❌ FuzzyDuplicateProcessor module not available"
        Logger.error(error_msg)
        {:error, error_msg}
      else
        Logger.info("✅ FuzzyDuplicateProcessor module confirmed available")
        Logger.info("🤖 Starting fuzzy duplicate processing with batch processing...")

        # Start the processing
        result = FuzzyDuplicateProcessor.process_all_venues([
          progress_callback: fn progress ->
            Logger.info("📊 Fuzzy duplicate processing progress: Batch #{progress.batch}/#{progress.total_batches}, Venues #{progress.venues_processed}/#{progress.total_venues}, Found #{progress.duplicates_found}, Stored #{progress.duplicates_stored}")
          end,
          batch_size: 50,
          min_confidence: 0.7,
          clear_existing: true
        ])

        case result do
          {:ok, results} ->
            Logger.info("🎉 FuzzyDuplicateProcessingJob COMPLETED successfully! Processed #{results.processed} venues, found #{results.duplicates_found} duplicates, stored #{results.duplicates_stored}")
            :ok

          {:error, reason} ->
            Logger.error("❌ FuzzyDuplicateProcessingJob FAILED with error: #{inspect(reason)}")
            {:error, reason}

          other ->
            Logger.warning("⚠️ FuzzyDuplicateProcessingJob returned unexpected result: #{inspect(other)}")
            :ok
        end
      end
    rescue
      error ->
        Logger.error("💥 FuzzyDuplicateProcessingJob CRASHED with exception: #{inspect(error)}")
        Logger.error("🔍 Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        {:error, "Job crashed: #{inspect(error)}"}
    end
  end
end

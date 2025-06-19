defmodule Mix.Tasks.ProcessFuzzyDuplicates do
  @moduledoc """
  Mix task to process all venues and populate the fuzzy duplicates table.

  This task uses the VenueDuplicateDetector service to find potential duplicates
  with confidence scores and stores them in the venue_fuzzy_duplicates table.

  ## Usage

      # Process all venues with default settings (min confidence 70%)
      mix process_fuzzy_duplicates

      # Clear existing records and reprocess with higher confidence threshold
      mix process_fuzzy_duplicates --clear --min-confidence 0.80

      # Process with smaller batches (useful for large datasets)
      mix process_fuzzy_duplicates --batch-size 50

  ## Options

  - `--clear` - Clear existing fuzzy duplicate records before processing
  - `--min-confidence` - Minimum confidence score to store (default: 0.70)
  - `--batch-size` - Number of venues to process per batch (default: 100)
  - `--quiet` - Suppress progress output
  """

  use Mix.Task
  require Logger

  alias TriviaAdvisor.Services.FuzzyDuplicateProcessor

  @shortdoc "Process venues to find fuzzy duplicates with confidence scores"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, _invalid} = OptionParser.parse(args,
      switches: [
        clear: :boolean,
        min_confidence: :float,
        batch_size: :integer,
        quiet: :boolean
      ],
      aliases: [
        c: :clear,
        m: :min_confidence,
        b: :batch_size,
        q: :quiet
      ]
    )

    # Normalize options
    process_opts = []
    process_opts = if opts[:clear], do: Keyword.put(process_opts, :clear_existing, true), else: process_opts
    process_opts = if opts[:min_confidence], do: Keyword.put(process_opts, :min_confidence, opts[:min_confidence]), else: process_opts
    process_opts = if opts[:batch_size], do: Keyword.put(process_opts, :batch_size, opts[:batch_size]), else: process_opts

    # Add progress callback unless quiet mode
    process_opts = if not opts[:quiet] do
      Keyword.put(process_opts, :progress_callback, &progress_callback/1)
    else
      process_opts
    end

    IO.puts """
    🔍 FUZZY DUPLICATE PROCESSING

    Starting fuzzy duplicate detection with options:
    #{format_options(process_opts)}
    """

    start_time = System.monotonic_time(:millisecond)

    case FuzzyDuplicateProcessor.process_all_venues(process_opts) do
      {:ok, results} ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time
        duration_sec = duration_ms / 1000

        IO.puts """

        ✅ PROCESSING COMPLETE!

        📊 RESULTS:
        - Venues processed: #{results.processed}
        - Duplicates found: #{results.duplicates_found}
        - Duplicates stored: #{results.duplicates_stored}
        - Processing time: #{Float.round(duration_sec, 2)}s

        💡 NEXT STEPS:
        1. Visit /admin/venues/duplicates to review fuzzy duplicates
        2. Use confidence filters to prioritize high-confidence matches
        3. Merge or reject duplicates as needed
        """

        # Show statistics
        show_statistics()

      {:error, reason} ->
        IO.puts """
        ❌ PROCESSING FAILED!

        Error: #{inspect(reason)}
        """
        System.halt(1)
    end
  end

  defp progress_callback(progress) do
    percent = Float.round(progress.venues_processed / progress.total_venues * 100, 1)

    IO.write("\r🔄 Batch #{progress.batch}/#{progress.total_batches} | ")
    IO.write("#{progress.venues_processed}/#{progress.total_venues} venues (#{percent}%) | ")
    IO.write("#{progress.duplicates_found} found, #{progress.duplicates_stored} stored")

    if progress.batch == progress.total_batches do
      IO.puts("")  # New line at the end
    end
  end

  defp format_options(opts) do
    opts
    |> Enum.map(fn {key, value} -> "  • #{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end

  defp show_statistics do
    stats = FuzzyDuplicateProcessor.get_statistics()

    if stats[:total] && stats[:total] > 0 do
      IO.puts """

      📈 FUZZY DUPLICATES STATISTICS:

      Total pairs: #{stats[:total]}

      By confidence level:
      • High confidence (90%+): #{stats[:high_confidence] || 0}
      • Medium confidence (75-89%): #{stats[:medium_confidence] || 0}
      • Low confidence (<75%): #{stats[:low_confidence] || 0}

      By status:
      • Pending review: #{stats[:pending] || 0}
      • Reviewed: #{stats[:reviewed] || 0}
      • Merged: #{stats[:merged] || 0}
      • Rejected: #{stats[:rejected] || 0}

      Average scores:
      • Confidence: #{if stats[:avg_confidence], do: Float.round(stats[:avg_confidence], 3), else: "N/A"}
      • Name similarity: #{if stats[:avg_name_similarity], do: Float.round(stats[:avg_name_similarity], 3), else: "N/A"}
      • Location similarity: #{if stats[:avg_location_similarity], do: Float.round(stats[:avg_location_similarity], 3), else: "N/A"}
      """
    end
  end
end

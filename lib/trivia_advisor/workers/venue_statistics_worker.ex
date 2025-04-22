defmodule TriviaAdvisor.Workers.VenueStatisticsWorker do
  @moduledoc """
  Oban worker that refreshes venue statistics daily.

  This worker runs via Oban's cron plugin to ensure venue statistics
  are regularly updated and cached, improving performance across the app
  by preventing on-demand recalculations during page loads.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query, warn: false
  require Logger
  alias TriviaAdvisor.VenueStatistics

  @impl Oban.Worker
  def perform(%{id: job_id} = _job) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting venue statistics refresh...")

    # Refresh venue statistics with force_refresh option
    venues_count = VenueStatistics.count_active_venues(force_refresh: true)
    venues_by_country = VenueStatistics.venues_by_country(force_refresh: true)
    countries_count = Enum.count(venues_by_country)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    Logger.info("""
    Venue statistics refresh completed.
    Duration: #{duration_ms}ms
    Total active venues: #{venues_count}
    Total countries with venues: #{countries_count}
    """)

    # Create metadata for the job
    metadata = %{
      venues_count: venues_count,
      countries_count: countries_count,
      duration_ms: duration_ms
    }

    # Update the job's meta column
    TriviaAdvisor.Repo.update_all(
      from(j in "oban_jobs", where: j.id == ^job_id),
      set: [meta: metadata]
    )

    :ok
  end

  @doc """
  Enqueues a job to refresh venue statistics.

  ## Examples

      iex> VenueStatisticsWorker.perform_async()
      {:ok, %Oban.Job{}}

  """
  def perform_async do
    %{}
    |> new()
    |> Oban.insert()
  end
end

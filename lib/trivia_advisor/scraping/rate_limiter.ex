defmodule TriviaAdvisor.Scraping.RateLimiter do
  @moduledoc """
  Handles rate limiting for API calls and job scheduling.

  This module provides centralized functionality to:
  1. Schedule jobs with incremental delays to avoid overwhelming external APIs
  2. Configure job retry parameters for consistent job configuration
  3. Provide consistent settings that can be changed in one place
  """

  require Logger

  # Default configuration - can be adjusted in one place
  @defaults %{
    # Basic job delay between each job in seconds
    job_delay_interval: 2,
    # Max attempts before giving up
    max_attempts: 5,
    # Job priority (lower numbers = higher priority)
    priority: 3
  }

  @doc """
  Returns the default max_attempts for detail jobs.
  """
  def max_attempts, do: @defaults.max_attempts

  @doc """
  Returns the default priority for detail jobs.
  """
  def priority, do: @defaults.priority

  @doc """
  Returns the default job delay interval in seconds.
  """
  def job_delay_interval, do: @defaults.job_delay_interval

  @doc """
  Schedules a batch of jobs with incremental delays.

  Takes a list of items and a function that creates and schedules a job for each item.
  Automatically adds an incremental delay to each job based on its position in the list.

  ## Parameters

  * `items` - The list of items to process (venues, events, etc.)
  * `job_fn` - Function that takes (item, index, scheduled_in) and returns an Oban job

  ## Returns

  * The number of successfully scheduled jobs

  ## Example

      RateLimiter.schedule_jobs_with_delay(
        venues,
        fn venue, index, delay ->
          %{url: venue.url, title: venue.title, source_id: source_id}
          |> DetailJob.new(schedule_in: delay)
        end
      )
  """
  def schedule_jobs_with_delay(items, job_fn) when is_list(items) and is_function(job_fn, 3) do
    Logger.info("🔄 Scheduling #{length(items)} jobs with rate limiting...")

    Enum.reduce(Enum.with_index(items), 0, fn {item, index}, count ->
      # Calculate delay based on index (in seconds)
      scheduled_in = index * job_delay_interval()

      # Calculate scheduled time (current time + delay)
      scheduled_at = DateTime.utc_now() |> DateTime.add(scheduled_in, :second)

      # Get the job changeset from the provided function
      job_changeset = job_fn.(item, index, scheduled_in)

      # For Oban 2.19.2 compatibility, set scheduled_at directly
      job_with_schedule = Map.put(job_changeset, :scheduled_at, scheduled_at)

      # Insert the job with Oban
      case Oban.insert(job_with_schedule) do
        {:ok, _job} ->
          Logger.info("📋 Scheduled job to run at #{DateTime.to_string(scheduled_at)}")
          count + 1
        {:error, error} ->
          Logger.error("❌ Failed to schedule job: #{inspect(error)}")
          count
      end
    end)
  end

  @doc """
  Schedules a batch of jobs with rate limiting, specifically for enqueuing detail jobs.

  This is a convenience wrapper for the common pattern of scheduling detail jobs from an index job.

  ## Parameters

  * `items` - The list of items to process (venues, events, etc.)
  * `job_module` - The Oban job module to use (e.g., QuestionOneDetailJob)
  * `args_fn` - Function that takes an item and returns the job args map

  ## Returns

  * The number of successfully scheduled jobs

  ## Example

      RateLimiter.schedule_detail_jobs(
        venues,
        QuestionOneDetailJob,
        fn venue ->
          %{url: venue.url, title: venue.title, source_id: source_id}
        end
      )
  """
  def schedule_detail_jobs(items, job_module, args_fn) when is_list(items) and is_function(args_fn, 1) do
    schedule_jobs_with_delay(items, fn item, _index, _delay ->
      # Just create the job without schedule_in
      args = args_fn.(item)
      job_module.new(args)
    end)
  end
end

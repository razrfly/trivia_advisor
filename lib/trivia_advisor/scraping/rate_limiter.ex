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
    job_delay_interval: 1,
    # Max attempts before giving up
    max_attempts: 5,
    # Job priority (lower numbers = higher priority)
    priority: 3,
    # Days threshold for skipping recently updated content
    skip_if_updated_within_days: 5,
    # Maximum jobs to schedule per hour
    max_jobs_per_hour: 50
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
  Returns the default days threshold for skipping recently updated content.
  """
  def skip_if_updated_within_days, do: @defaults.skip_if_updated_within_days

  @doc """
  Returns the maximum number of jobs to schedule per hour.
  """
  def max_jobs_per_hour, do: @defaults.max_jobs_per_hour

  @doc """
  Checks if a job should force update all venues regardless of when they were last updated.

  ## Parameters

  * `args` - The job arguments map

  ## Returns

  * Boolean indicating whether to force update all venues
  """
  def force_update?(args) when is_map(args) do
    Map.get(args, "force_update", false) || Map.get(args, :force_update, false)
  end

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
    schedule_jobs_with_delay(items, fn item, _index, delay ->
      # Just create the job with the calculated delay
      args = args_fn.(item)
      job_module.new(args, schedule_in: delay)
    end)
  end

  @doc """
  Schedules a batch of jobs distributed across hours to prevent overwhelming systems.

  This function limits the number of jobs scheduled per hour according to max_jobs_per_hour.

  ## Parameters

  * `items` - The list of items to process (venues, events, etc.)
  * `job_module` - The Oban job module to use (e.g., QuestionOneDetailJob)
  * `args_fn` - Function that takes an item and returns the job args map

  ## Returns

  * The number of successfully scheduled jobs

  ## Example

      RateLimiter.schedule_hourly_capped_jobs(
        venues,
        QuestionOneDetailJob,
        fn venue ->
          %{url: venue.url, title: venue.title, source_id: source_id}
        end
      )
  """
  def schedule_hourly_capped_jobs(items, job_module, args_fn) when is_list(items) and is_function(args_fn, 1) do
    total_items = length(items)
    jobs_per_hour = max_jobs_per_hour()

    # Calculate how many hours we need to distribute these jobs
    hours_needed = ceil(total_items / jobs_per_hour)

    Logger.info("📊 Distributing #{total_items} jobs across #{hours_needed} hours (max #{jobs_per_hour}/hour)")

    Enum.with_index(items)
    |> Enum.reduce(0, fn {item, index}, count ->
      # Calculate which hour this job belongs in
      hour = div(index, jobs_per_hour)
      position_in_hour = rem(index, jobs_per_hour)

      # Calculate seconds between jobs within an hour
      seconds_per_job = floor(3600 / jobs_per_hour)

      # Calculate total delay: hours + position within the hour
      delay_seconds = (hour * 3600) + (position_in_hour * seconds_per_job)

      # Generate scheduled time for logging
      scheduled_at = DateTime.utc_now() |> DateTime.add(delay_seconds, :second)
      scheduled_hour = DateTime.to_time(scheduled_at) |> Time.to_string() |> String.slice(0, 5)

      # Create and schedule the job
      args = args_fn.(item)
      job = job_module.new(args, schedule_in: delay_seconds)

      case Oban.insert(job) do
        {:ok, _job} ->
          if rem(index, 50) == 0 or index == total_items - 1 do
            Logger.info("📋 Scheduled job #{index + 1}/#{total_items} for hour +#{hour} at #{scheduled_hour}")
          end
          count + 1

        {:error, error} ->
          Logger.error("❌ Failed to schedule job: #{inspect(error)}")
          count
      end
    end)
  end
end

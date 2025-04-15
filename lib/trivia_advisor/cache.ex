defmodule TriviaAdvisor.Cache do
  @moduledoc """
  Simple caching mechanism using ETS for in-memory storage.
  Provides functions for storing and retrieving data with TTL.
  """

  use GenServer

  @table_name :trivia_advisor_cache

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Retrieve a cached value by key, or compute and store if missing/expired.

  ## Parameters
    * `key` - The cache key
    * `ttl_seconds` - Time to live in seconds (default: 86400 = 24 hours)
    * `compute_fun` - Function that computes the value if not in cache
  """
  def get_or_store(key, ttl_seconds \\ 86400, compute_fun) when is_function(compute_fun, 0) do
    case lookup(key) do
      {:ok, value} ->
        value

      {:expired, _} ->
        # Cache expired, recompute and store
        value = compute_fun.()
        store(key, value, ttl_seconds)
        value

      :not_found ->
        # Not in cache, compute and store
        value = compute_fun.()
        store(key, value, ttl_seconds)
        value
    end
  end

  @doc """
  Look up a key in the cache.
  Returns {:ok, value}, {:expired, value}, or :not_found
  """
  def lookup(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, value}
        else
          {:expired, value}
        end
      [] ->
        :not_found
    end
  end

  @doc """
  Simplified lookup that returns the value or nil.
  This is for backward compatibility with older code.
  """
  def get(key) do
    case lookup(key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  @doc """
  Store a value in the cache with expiration.
  """
  def store(key, value, ttl_seconds) do
    expires_at = DateTime.utc_now() |> DateTime.add(ttl_seconds, :second)
    :ets.insert(@table_name, {key, value, expires_at})
    value
  end

  @doc """
  Simplified store function that accepts options.
  This is for backward compatibility with older code.
  """
  def put(key, value, opts \\ []) do
    ttl_seconds = Keyword.get(opts, :ttl, 86400)
    store(key, value, ttl_seconds)
  end

  @doc """
  Clear the entire cache.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # Server API

  @impl true
  def init(_args) do
    # Create the ETS table if it doesn't exist
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :set, :public])
    end

    # Schedule periodic cleanup of expired entries
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Helper functions

  defp schedule_cleanup do
    # Run cleanup every hour
    Process.send_after(self(), :cleanup, :timer.hours(1))
  end

  defp cleanup_expired do
    now = DateTime.utc_now()

    # Find all expired entries and remove them
    :ets.select_delete(@table_name, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])
  end
end

defmodule TriviaAdvisor.Cache do
  @moduledoc """
  Simple caching mechanism using ETS for in-memory storage.
  Provides functions for storing and retrieving data with TTL.

  This cache is used throughout the application to optimize performance
  for frequently accessed data, particularly for statistics and visualization data.
  """

  use GenServer

  @table_name :trivia_advisor_cache
  @default_ttl 86_400 # 24 hours in seconds

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

  ## Examples

      iex> Cache.get_or_store("stats:user_count", 3600, fn -> Repo.aggregate(User, :count) end)
      42

  """
  def get_or_store(key, ttl_seconds \\ @default_ttl, compute_fun) when is_function(compute_fun, 0) do
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

  ## Parameters
    * `key` - The cache key

  ## Examples

      iex> Cache.lookup("stats:user_count")
      {:ok, 42}

      iex> Cache.lookup("non_existent_key")
      :not_found
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

  ## Parameters
    * `key` - The cache key

  ## Examples

      iex> Cache.get("stats:user_count")
      42

      iex> Cache.get("non_existent_key")
      nil
  """
  def get(key) do
    case lookup(key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  @doc """
  Store a value in the cache with expiration.

  ## Parameters
    * `key` - The cache key
    * `value` - The value to store
    * `ttl_seconds` - Time to live in seconds

  ## Examples

      iex> Cache.store("stats:user_count", 42, 3600)
      42
  """
  def store(key, value, ttl_seconds) do
    expires_at = DateTime.utc_now() |> DateTime.add(ttl_seconds, :second)
    :ets.insert(@table_name, {key, value, expires_at})
    value
  end

  @doc """
  Simplified store function that accepts options.

  ## Parameters
    * `key` - The cache key
    * `value` - The value to store
    * `opts` - Options list with `:ttl` in seconds (default: 86400 = 24 hours)

  ## Examples

      iex> Cache.put("stats:user_count", 42, ttl: 3600)
      42
  """
  def put(key, value, opts \\ []) do
    ttl_seconds = Keyword.get(opts, :ttl, @default_ttl)
    store(key, value, ttl_seconds)
  end

  @doc """
  Clear the entire cache.

  ## Examples

      iex> Cache.clear()
      :ok
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Clear a specific key from the cache.

  ## Parameters
    * `key` - The cache key to remove

  ## Examples

      iex> Cache.delete("stats:user_count")
      :ok
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Clear all keys with a specific prefix.
  Useful for invalidating related caches.

  ## Parameters
    * `prefix` - The prefix to match against keys

  ## Examples

      iex> Cache.delete_by_prefix("stats:")
      5  # Returns the number of deleted entries
  """
  def delete_by_prefix(prefix) when is_binary(prefix) do
    # Use match to find all keys that start with the prefix
    # This is more efficient than traversing the entire table
    pattern = {:"$1", :_, :_}
    guard = [{:==, {:binary_part, :"$1", {0, byte_size(prefix)}}, prefix}]
    keys = :ets.select(@table_name, [{pattern, guard, [:"$1"]}])

    # Delete each matching key
    Enum.each(keys, &:ets.delete(@table_name, &1))

    length(keys)
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
    count = cleanup_expired()
    # Log cleanup for monitoring purposes in production
    if count > 0 do
      require Logger
      Logger.debug("Cache cleanup: removed #{count} expired entries")
    end

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
    # Returns the count of deleted entries
    :ets.select_delete(@table_name, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])
  end
end

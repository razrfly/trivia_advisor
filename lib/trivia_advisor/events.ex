defmodule TriviaAdvisor.Events do
  @moduledoc """
  The Events context.
  """

  import Ecto.Query, warn: false
  alias TriviaAdvisor.Repo

  alias TriviaAdvisor.Events.Event

  @doc """
  Returns the list of events.

  ## Examples

      iex> list_events()
      [%Event{}, ...]

  """
  def list_events do
    Repo.all(Event)
  end

  @doc """
  Gets a single event.

  Raises `Ecto.NoResultsError` if the Event does not exist.

  ## Examples

      iex> get_event!(123)
      %Event{}

      iex> get_event!(456)
      ** (Ecto.NoResultsError)

  """
  def get_event!(id), do: Repo.get!(Event, id)

  @doc """
  Creates a event.

  ## Examples

      iex> create_event(%{field: value})
      {:ok, %Event{}}

      iex> create_event(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a event.

  ## Examples

      iex> update_event(event, %{field: new_value})
      {:ok, %Event{}}

      iex> update_event(event, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a event.

  ## Examples

      iex> delete_event(event)
      {:ok, %Event{}}

      iex> delete_event(event)
      {:error, %Ecto.Changeset{}}

  """
  def delete_event(%Event{} = event) do
    Repo.delete_with_callbacks(event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.

  ## Examples

      iex> change_event(event)
      %Ecto.Changeset{data: %Event{}}

  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  alias TriviaAdvisor.Events.EventSource

  @doc """
  Returns the list of event_sources.

  ## Examples

      iex> list_event_sources()
      [%EventSource{}, ...]

  """
  def list_event_sources do
    Repo.all(EventSource)
    |> Repo.preload([:event, :source])
  end

  @doc """
  Gets a single event_source.

  Raises `Ecto.NoResultsError` if the Event source does not exist.

  ## Examples

      iex> get_event_source!(123)
      %EventSource{}

      iex> get_event_source!(456)
      ** (Ecto.NoResultsError)

  """
  def get_event_source!(id) do
    EventSource
    |> Repo.get!(id)
    |> Repo.preload([:event, :source])
  end

  @doc """
  Creates a event_source.

  ## Examples

      iex> create_event_source(%{field: value})
      {:ok, %EventSource{}}

      iex> create_event_source(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_event_source(attrs) do
    now = DateTime.utc_now()
    attrs = Map.put(attrs, :last_seen_at, now)

    changeset = EventSource.changeset(%EventSource{}, attrs)

    if not changeset.valid? do
      {:error, changeset}
    else
      # First try to find existing record by event_id and source_url
      query_by_url = from es in EventSource,
        where: es.event_id == ^attrs.event_id and es.source_url == ^attrs.source_url

      # Also check for event_id and source_id constraint
      query_by_source = from es in EventSource,
        where: es.event_id == ^attrs.event_id and es.source_id == ^attrs.source_id

      case {Repo.one(query_by_url), Repo.one(query_by_source)} do
        {nil, nil} ->
          # No existing record found, try inserting
          %EventSource{}
          |> EventSource.changeset(attrs)
          |> Repo.insert()
          |> case do
            {:ok, event_source} ->
              {:ok, event_source}
            {:error, changeset} ->
              # Check if this is a unique constraint error
              constraint_error? = Enum.any?(changeset.errors, fn
                {_, {_, opts}} -> Keyword.get(opts, :constraint) == :unique
                _ -> false
              end)

              if constraint_error? do
                # Race condition - try to find and update the record that now exists
                existing_by_url = Repo.one(query_by_url)
                existing_by_source = Repo.one(query_by_source)
                existing = existing_by_url || existing_by_source

                if existing do
                  # Update existing record, merging metadata
                  new_metadata = attrs.metadata || %{}
                  existing_metadata = existing.metadata || %{}
                  merged_metadata = Map.merge(existing_metadata, new_metadata)

                  existing
                  |> EventSource.changeset(%{
                    last_seen_at: now,
                    metadata: merged_metadata
                  })
                  |> Repo.update()
                else
                  {:error, changeset}
                end
              else
                {:error, changeset}
              end
          end

        {existing, _} when not is_nil(existing) ->
          # Update existing record found by URL, merging metadata
          new_metadata = attrs.metadata || %{}
          existing_metadata = existing.metadata || %{}
          merged_metadata = Map.merge(existing_metadata, new_metadata)

          existing
          |> EventSource.changeset(%{
            last_seen_at: now,
            metadata: merged_metadata
          })
          |> Repo.update()

        {nil, existing} when not is_nil(existing) ->
          # Update existing record found by source_id, merging metadata
          new_metadata = attrs.metadata || %{}
          existing_metadata = existing.metadata || %{}
          merged_metadata = Map.merge(existing_metadata, new_metadata)

          existing
          |> EventSource.changeset(%{
            last_seen_at: now,
            source_url: attrs.source_url, # Update the source_url to match
            metadata: merged_metadata
          })
          |> Repo.update()
      end
    end
  end

  @doc """
  Updates a event_source.

  ## Examples

      iex> update_event_source(event_source, %{field: new_value})
      {:ok, %EventSource{}}

      iex> update_event_source(event_source, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_event_source(%EventSource{} = event_source, attrs) do
    event_source
    |> EventSource.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a event_source.

  ## Examples

      iex> delete_event_source(event_source)
      {:ok, %EventSource{}}

      iex> delete_event_source(event_source)
      {:error, %Ecto.Changeset{}}

  """
  def delete_event_source(%EventSource{} = event_source) do
    Repo.delete_with_callbacks(event_source)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event_source changes.

  ## Examples

      iex> change_event_source(event_source)
      %Ecto.Changeset{data: %EventSource{}}

  """
  def change_event_source(%EventSource{} = event_source, attrs \\ %{}) do
    EventSource.changeset(event_source, attrs)
  end

  @doc """
  Creates or updates an event source entry.
  Updates last_seen_at and merges metadata if the event source already exists.
  Returns {:ok, event_source} with the created or updated record.
  """
  def create_event_source(event, source_url, metadata) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # First try to find existing record
    query = from es in EventSource,
      where: es.event_id == ^event.id and es.source_url == ^source_url

    case Repo.one(query) do
      # Create new record if none exists
      nil ->
        %EventSource{}
        |> EventSource.changeset(%{
          event_id: event.id,
          source_url: source_url,
          last_seen_at: now,
          status: "active",
          metadata: metadata,
          source_id: event.source_id
        })
        |> Repo.insert()
        |> case do
          {:error, changeset} = error ->
            errors = changeset.errors
            has_unique_constraint = Enum.any?(errors, fn
              {field, {_, opts}} ->
                field == :event_id and Keyword.get(opts, :constraint) == :unique
              _ ->
                false
            end)

            if has_unique_constraint do
              # If we hit the unique constraint, try to find and update the existing record
              case Repo.one(query) do
                nil -> error
                found_event_source ->
                  existing_metadata = found_event_source.metadata || %{}
                  new_metadata = metadata || %{}
                  merged_metadata = Map.merge(existing_metadata, new_metadata)

                  update_event_source(found_event_source, %{
                    last_seen_at: now,
                    metadata: merged_metadata
                  })
              end
            else
              error
            end
          other -> other
        end

      # Update existing record, merging metadata
      event_source ->
        existing_metadata = event_source.metadata || %{}
        new_metadata = metadata || %{}
        merged_metadata = Map.merge(existing_metadata, new_metadata)

        event_source
        |> EventSource.changeset(%{
          last_seen_at: now,
          metadata: merged_metadata
        })
        |> Repo.update()
    end
  end

  @doc """
  Finds or creates an event based on venue_id and day_of_week.
  Updates existing event if found with new attributes.
  """
  def find_or_create_event(attrs) do
    query = from e in Event,
      where: e.venue_id == ^attrs.venue_id and
             e.day_of_week == ^attrs.day_of_week,
      limit: 1

    case Repo.one(query) do
      nil -> create_event(attrs)
      event -> update_event(event, attrs)
    end
  end
end

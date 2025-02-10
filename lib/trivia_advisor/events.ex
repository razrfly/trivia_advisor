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
    Repo.delete(event)
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
    Repo.all(EventSource) |> Repo.preload([:event, :source])
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
  def get_event_source!(id), do: Repo.get!(EventSource, id) |> Repo.preload([:event, :source])

  @doc """
  Creates a event_source.

  ## Examples

      iex> create_event_source(%{field: value})
      {:ok, %EventSource{}}

      iex> create_event_source(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_event_source(attrs \\ %{}) do
    %EventSource{}
    |> EventSource.changeset(attrs)
    |> Repo.insert()
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
    Repo.delete(event_source)
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
end

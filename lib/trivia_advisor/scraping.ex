defmodule TriviaAdvisor.Scraping do
  @moduledoc """
  The Scraping context.
  """

  import Ecto.Query, warn: false
  alias TriviaAdvisor.Repo

  alias TriviaAdvisor.Scraping.Source

  @doc """
  Returns the list of sources.

  ## Examples

      iex> list_sources()
      [%Source{}, ...]

  """
  def list_sources do
    Repo.all(Source)
  end

  @doc """
  Gets a single source.

  Raises `Ecto.NoResultsError` if the Source does not exist.

  ## Examples

      iex> get_source!(123)
      %Source{}

      iex> get_source!(456)
      ** (Ecto.NoResultsError)

  """
  def get_source!(id), do: Repo.get!(Source, id)

  @doc """
  Creates a source.

  ## Examples

      iex> create_source(%{field: value})
      {:ok, %Source{}}

      iex> create_source(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a source.

  ## Examples

      iex> update_source(source, %{field: new_value})
      {:ok, %Source{}}

      iex> update_source(source, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a source.

  ## Examples

      iex> delete_source(source)
      {:ok, %Source{}}

      iex> delete_source(source)
      {:error, %Ecto.Changeset{}}

  """
  def delete_source(%Source{} = source) do
    Repo.delete(source)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking source changes.

  ## Examples

      iex> change_source(source)
      %Ecto.Changeset{data: %Source{}}

  """
  def change_source(%Source{} = source, attrs \\ %{}) do
    Source.changeset(source, attrs)
  end

  alias TriviaAdvisor.Scraping.ScrapeLog

  @doc """
  Returns the list of scrape_logs.

  ## Examples

      iex> list_scrape_logs()
      [%ScrapeLog{}, ...]

  """
  def list_scrape_logs do
    Repo.all(ScrapeLog)
  end

  @doc """
  Gets a single scrape_log.

  Raises `Ecto.NoResultsError` if the Scrape log does not exist.

  ## Examples

      iex> get_scrape_log!(123)
      %ScrapeLog{}

      iex> get_scrape_log!(456)
      ** (Ecto.NoResultsError)

  """
  def get_scrape_log!(id), do: Repo.get!(ScrapeLog, id)

  @doc """
  Creates a scrape_log.

  ## Examples

      iex> create_scrape_log(%{field: value})
      {:ok, %ScrapeLog{}}

      iex> create_scrape_log(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_scrape_log(attrs \\ %{}) do
    %ScrapeLog{}
    |> ScrapeLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a scrape_log.

  ## Examples

      iex> update_scrape_log(scrape_log, %{field: new_value})
      {:ok, %ScrapeLog{}}

      iex> update_scrape_log(scrape_log, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_scrape_log(%ScrapeLog{} = scrape_log, attrs) do
    scrape_log
    |> ScrapeLog.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a scrape_log.

  ## Examples

      iex> delete_scrape_log(scrape_log)
      {:ok, %ScrapeLog{}}

      iex> delete_scrape_log(scrape_log)
      {:error, %Ecto.Changeset{}}

  """
  def delete_scrape_log(%ScrapeLog{} = scrape_log) do
    Repo.delete(scrape_log)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking scrape_log changes.

  ## Examples

      iex> change_scrape_log(scrape_log)
      %Ecto.Changeset{data: %ScrapeLog{}}

  """
  def change_scrape_log(%ScrapeLog{} = scrape_log, attrs \\ %{}) do
    ScrapeLog.changeset(scrape_log, attrs)
  end
end

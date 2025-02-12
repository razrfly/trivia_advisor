defmodule TriviaAdvisor.ScrapingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TriviaAdvisor.Scraping` context.
  """

  @doc """
  Generate a unique source slug.
  """
  def unique_source_slug, do: "some slug#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique source website_url.
  """
  def unique_source_website_url, do: "some website_url#{System.unique_integer([:positive])}"

  @doc """
  Generate a source.
  """
  def source_fixture(attrs \\ %{}) do
    {:ok, source} =
      attrs
      |> Enum.into(%{
        slug: unique_source_slug(),
        title: "some title",
        website_url: unique_source_website_url()
      })
      |> TriviaAdvisor.Scraping.create_source()

    source
  end

  @doc """
  Generate a scrape_log.
  """
  def scrape_log_fixture(attrs \\ %{}) do
    source = source_fixture()

    {:ok, scrape_log} =
      attrs
      |> Enum.into(%{
        success: true,
        event_count: 42,
        error: %{},
        metadata: %{},
        source_id: source.id
      })
      |> TriviaAdvisor.Scraping.create_scrape_log()

    scrape_log
  end
end

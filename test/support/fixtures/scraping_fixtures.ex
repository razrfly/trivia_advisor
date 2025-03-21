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
    unique_id = System.unique_integer([:positive])

    {:ok, source} =
      attrs
      |> Enum.into(%{
        name: "some name",
        website_url: "https://example.com/#{unique_id}",
        slug: "source-#{unique_id}"
      })
      |> TriviaAdvisor.Scraping.create_source()

    source
  end

  # The ScrapeLog module has been deprecated and removed.
  # All scrape tracking is now done via Oban job metadata.
end

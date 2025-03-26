defmodule TriviaAdvisor.ScrapingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  scraping-related fixtures.
  """

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source

  @doc """
  Generate a unique source slug.
  """
  def unique_source_slug, do: "some slug#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique source website_url.
  """
  def unique_source_website_url, do: "some website_url#{System.unique_integer([:positive])}"

  @doc """
  Creates a source.
  """
  def source_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{
      name: "Quiz Meisters",
      slug: "quiz-meisters",
      website_url: "https://quizmeisters.com"
    })

    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert!()
  end

  # The ScrapeLog module has been deprecated and removed.
  # All scrape tracking is now done via Oban job metadata.
end

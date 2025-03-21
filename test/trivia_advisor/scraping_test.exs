defmodule TriviaAdvisor.ScrapingTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Scraping

  describe "sources" do
    alias TriviaAdvisor.Scraping.Source

    import TriviaAdvisor.ScrapingFixtures

    @valid_attrs %{name: "some name", website_url: "https://example.com", slug: "some slug"}
    @update_attrs %{name: "some updated name", website_url: "https://example.com/updated", slug: "some updated slug"}
    @invalid_attrs %{name: nil, website_url: nil, slug: nil}

    test "list_sources/0 returns all sources" do
      source = source_fixture()
      sources = Scraping.list_sources()
      assert source in sources
    end

    test "get_source!/1 returns the source with given id" do
      source = source_fixture()
      assert Scraping.get_source!(source.id) == source
    end

    test "create_source/1 with valid data creates a source" do
      assert {:ok, %Source{} = source} = Scraping.create_source(@valid_attrs)
      assert source.name == "some name"
      assert source.website_url == "https://example.com"
      assert source.slug == "some slug"
    end

    test "create_source/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Scraping.create_source(@invalid_attrs)
    end

    test "update_source/2 with valid data updates the source" do
      source = source_fixture()
      assert {:ok, %Source{} = source} = Scraping.update_source(source, @update_attrs)
      assert source.name == "some updated name"
      assert source.website_url == "https://example.com/updated"
      assert source.slug == "some updated slug"
    end

    test "update_source/2 with invalid data returns error changeset" do
      source = source_fixture()
      assert {:error, %Ecto.Changeset{}} = Scraping.update_source(source, @invalid_attrs)
      assert source == Scraping.get_source!(source.id)
    end

    test "delete_source/1 deletes the source" do
      source = source_fixture()
      assert {:ok, %Source{}} = Scraping.delete_source(source)
      assert_raise Ecto.NoResultsError, fn -> Scraping.get_source!(source.id) end
    end

    test "change_source/1 returns a source changeset" do
      source = source_fixture()
      assert %Ecto.Changeset{} = Scraping.change_source(source)
    end
  end

  describe "scrape_logs" do
    # The ScrapeLog module has been deprecated and removed.
    # All scrape tracking is now done via Oban job metadata.
    # See TriviaAdvisor.Scraping.Helpers.JobMetadata for more information.
  end
end

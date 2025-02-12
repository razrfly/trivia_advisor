defmodule TriviaAdvisor.ScrapingTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Scraping

  describe "sources" do
    alias TriviaAdvisor.Scraping.Source

    import TriviaAdvisor.ScrapingFixtures

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
      valid_attrs = %{name: "some name", website_url: "some website_url", slug: "some slug"}

      assert {:ok, %Source{} = source} = Scraping.create_source(valid_attrs)
      assert source.name == "some name"
      assert source.website_url == "some website_url"
      assert source.slug == "some slug"
    end

    test "create_source/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Scraping.create_source(@invalid_attrs)
    end

    test "update_source/2 with valid data updates the source" do
      source = source_fixture()
      update_attrs = %{name: "some updated name", website_url: "some updated website_url", slug: "some updated slug"}

      assert {:ok, %Source{} = source} = Scraping.update_source(source, update_attrs)
      assert source.name == "some updated name"
      assert source.website_url == "some updated website_url"
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
    alias TriviaAdvisor.Scraping.ScrapeLog

    import TriviaAdvisor.ScrapingFixtures

    @invalid_attrs %{error: nil, metadata: nil, success: nil, event_count: nil}

    test "list_scrape_logs/0 returns all scrape_logs" do
      scrape_log = scrape_log_fixture()
      assert Scraping.list_scrape_logs() == [scrape_log]
    end

    test "get_scrape_log!/1 returns the scrape_log with given id" do
      scrape_log = scrape_log_fixture()
      assert Scraping.get_scrape_log!(scrape_log.id) == scrape_log
    end

    test "create_scrape_log/1 with valid data creates a scrape_log" do
      source = source_fixture()
      valid_attrs = %{
        error: %{},
        metadata: %{},
        success: true,
        event_count: 42,
        source_id: source.id
      }

      assert {:ok, %ScrapeLog{} = scrape_log} = Scraping.create_scrape_log(valid_attrs)
      assert scrape_log.error == %{}
      assert scrape_log.metadata == %{}
      assert scrape_log.success == true
      assert scrape_log.event_count == 42
    end

    test "create_scrape_log/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Scraping.create_scrape_log(@invalid_attrs)
    end

    test "update_scrape_log/2 with valid data updates the scrape_log" do
      scrape_log = scrape_log_fixture()
      update_attrs = %{error: %{}, metadata: %{}, success: false, event_count: 43}

      assert {:ok, %ScrapeLog{} = scrape_log} = Scraping.update_scrape_log(scrape_log, update_attrs)
      assert scrape_log.error == %{}
      assert scrape_log.metadata == %{}
      assert scrape_log.success == false
      assert scrape_log.event_count == 43
    end

    test "update_scrape_log/2 with invalid data returns error changeset" do
      scrape_log = scrape_log_fixture()
      assert {:error, %Ecto.Changeset{}} =
        Scraping.update_scrape_log(scrape_log, %{source_id: nil})  # Use required field
    end

    test "delete_scrape_log/1 deletes the scrape_log" do
      scrape_log = scrape_log_fixture()
      assert {:ok, %ScrapeLog{}} = Scraping.delete_scrape_log(scrape_log)
      assert_raise Ecto.NoResultsError, fn -> Scraping.get_scrape_log!(scrape_log.id) end
    end

    test "change_scrape_log/1 returns a scrape_log changeset" do
      scrape_log = scrape_log_fixture()
      assert %Ecto.Changeset{} = Scraping.change_scrape_log(scrape_log)
    end
  end
end

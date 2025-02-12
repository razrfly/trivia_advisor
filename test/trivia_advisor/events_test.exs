defmodule TriviaAdvisor.EventsTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Events

  describe "events" do
    alias TriviaAdvisor.Events.Event

    import TriviaAdvisor.EventsFixtures

    @invalid_attrs %{description: nil, title: nil, day_of_week: nil, start_time: nil, frequency: nil, entry_fee_cents: nil}

    @valid_attrs %{
      title: "some title",
      description: "some description",
      start_time: ~T[14:00:00],
      day_of_week: 42,
      frequency: 42,
      entry_fee_cents: 42,
      venue_id: nil  # Will be set in the test
    }

    test "list_events/0 returns all events" do
      event = event_fixture()
      assert Events.list_events() == [event]
    end

    test "get_event!/1 returns the event with given id" do
      event = event_fixture()
      assert Events.get_event!(event.id) == event
    end

    test "create_event/1 with valid data creates a event" do
      venue = TriviaAdvisor.LocationsFixtures.venue_fixture()
      valid_attrs = Map.put(@valid_attrs, :venue_id, venue.id)
      assert {:ok, %Event{} = event} = Events.create_event(valid_attrs)
      assert event.description == "some description"
      assert event.title == "some title"
      assert event.day_of_week == 42
      assert event.start_time == ~T[14:00:00]
      assert event.frequency == 42
      assert event.entry_fee_cents == 42
    end

    test "create_event/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event(@invalid_attrs)
    end

    test "update_event/2 with valid data updates the event" do
      event = event_fixture()
      update_attrs = %{description: "some updated description", title: "some updated title", day_of_week: 43, start_time: ~T[15:01:01], frequency: 43, entry_fee_cents: 43}

      assert {:ok, %Event{} = event} = Events.update_event(event, update_attrs)
      assert event.description == "some updated description"
      assert event.title == "some updated title"
      assert event.day_of_week == 43
      assert event.start_time == ~T[15:01:01]
      assert event.frequency == 43
      assert event.entry_fee_cents == 43
    end

    test "update_event/2 with invalid data returns error changeset" do
      event = event_fixture()
      assert {:error, %Ecto.Changeset{}} = Events.update_event(event, @invalid_attrs)
      assert event == Events.get_event!(event.id)
    end

    test "delete_event/1 deletes the event" do
      event = event_fixture()
      assert {:ok, %Event{}} = Events.delete_event(event)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(event.id) end
    end

    test "change_event/1 returns a event changeset" do
      event = event_fixture()
      assert %Ecto.Changeset{} = Events.change_event(event)
    end
  end

  describe "event_sources" do
    alias TriviaAdvisor.Events.EventSource

    import TriviaAdvisor.EventsFixtures

    @invalid_attrs %{status: nil, metadata: nil, source_url: nil, last_seen_at: nil}

    @valid_attrs %{
      status: "some status",
      metadata: %{},
      source_url: "some source_url",
      last_seen_at: ~U[2025-02-09 21:21:00Z],
      event_id: nil,  # Will be set in the test
      source_id: nil  # Will be set in the test
    }

    test "list_event_sources/0 returns all event_sources" do
      event_source = event_source_fixture()
      assert Events.list_event_sources() == [event_source]
    end

    test "get_event_source!/1 returns the event_source with given id" do
      event_source = event_source_fixture()
      assert Events.get_event_source!(event_source.id) == event_source
    end

    test "create_event_source/1 with valid data creates a event_source" do
      event = TriviaAdvisor.EventsFixtures.event_fixture()
      source = TriviaAdvisor.ScrapingFixtures.source_fixture()
      valid_attrs = @valid_attrs
        |> Map.put(:event_id, event.id)
        |> Map.put(:source_id, source.id)
      assert {:ok, %EventSource{} = event_source} = Events.create_event_source(valid_attrs)
      assert event_source.status == "some status"
      assert event_source.metadata == %{}
      assert event_source.source_url == "some source_url"
      assert event_source.last_seen_at == ~U[2025-02-09 21:21:00Z]
    end

    test "create_event_source/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event_source(@invalid_attrs)
    end

    test "update_event_source/2 with valid data updates the event_source" do
      event_source = event_source_fixture()
      update_attrs = %{status: "some updated status", metadata: %{}, source_url: "some updated source_url", last_seen_at: ~U[2025-02-10 21:21:00Z]}

      assert {:ok, %EventSource{} = event_source} = Events.update_event_source(event_source, update_attrs)
      assert event_source.status == "some updated status"
      assert event_source.metadata == %{}
      assert event_source.source_url == "some updated source_url"
      assert event_source.last_seen_at == ~U[2025-02-10 21:21:00Z]
    end

    test "update_event_source/2 with invalid data returns error changeset" do
      event_source = event_source_fixture()
      assert {:error, %Ecto.Changeset{}} = Events.update_event_source(event_source, @invalid_attrs)
      assert event_source == Events.get_event_source!(event_source.id)
    end

    test "delete_event_source/1 deletes the event_source" do
      event_source = event_source_fixture()
      assert {:ok, %EventSource{}} = Events.delete_event_source(event_source)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event_source!(event_source.id) end
    end

    test "change_event_source/1 returns a event_source changeset" do
      event_source = event_source_fixture()
      assert %Ecto.Changeset{} = Events.change_event_source(event_source)
    end
  end
end

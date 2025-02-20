defmodule TriviaAdvisor.EventsTest do
  use TriviaAdvisor.DataCase

  alias TriviaAdvisor.Events
  alias TriviaAdvisor.Events.{Event, EventSource}

  describe "events" do
    alias TriviaAdvisor.Events.Event

    import TriviaAdvisor.EventsFixtures

    @invalid_attrs %{
      name: nil,
      description: nil,
      day_of_week: nil,
      start_time: nil,
      frequency: nil,
      entry_fee_cents: nil,
      venue_id: nil
    }

    @valid_attrs %{
      name: "some name",
      description: "some description",
      start_time: ~T[14:00:00],
      day_of_week: 2,
      frequency: :weekly,
      entry_fee_cents: 42,
      venue_id: nil  # Will be set in the test
    }

    @update_attrs %{
      name: "some updated name",
      description: "some updated description",
      start_time: ~T[15:01:01],
      day_of_week: 3,
      frequency: :monthly,
      entry_fee_cents: 43
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
      assert event.name == "some name"
      assert event.day_of_week == 2
      assert event.start_time == ~T[14:00:00]
      assert event.frequency == :weekly
      assert event.entry_fee_cents == 42
    end

    test "create_event/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event(@invalid_attrs)
    end

    test "update_event/2 with valid data updates the event" do
      event = event_fixture()
      update_attrs = @update_attrs
        |> Map.put(:venue_id, event.venue_id)  # Keep the same venue_id

      assert {:ok, %Event{} = event} = Events.update_event(event, update_attrs)
      assert event.description == "some updated description"
      assert event.name == "some updated name"
      assert event.day_of_week == 3
      assert event.start_time == ~T[15:01:01]
      assert event.frequency == :monthly  # This should now pass since we're using @update_attrs
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
      assert %DateTime{} = event_source.last_seen_at  # Just verify it's a DateTime
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

    setup do
      venue = TriviaAdvisor.LocationsFixtures.venue_fixture()
      # Create a test source first
      {:ok, source} = TriviaAdvisor.Scraping.create_source(%{
        name: "Test Source",
        url: "https://example.com",
        website_url: "https://example.com"
      })

      {:ok, event} = Events.create_event(%{
        name: "Test Quiz",
        day_of_week: 2,
        start_time: ~T[19:00:00],
        frequency: "weekly",
        venue_id: venue.id
      })

      %{event: event, source: source}
    end

    test "create_event_source/3 updates last_seen_at instead of duplicating", %{event: event, source: source} do
      source_url = "https://example.com/quiz"
      metadata = %{"key" => "value"}

      {:ok, source1} = Events.create_event_source(%{
        event_id: event.id,
        source_id: source.id,
        source_url: source_url,
        metadata: metadata
      })
      assert source1.last_seen_at != nil
      first_seen = source1.last_seen_at

      # Wait to ensure timestamp differs
      Process.sleep(1000)

      # Second creation should update
      {:ok, source2} = Events.create_event_source(%{
        event_id: event.id,
        source_id: source.id,
        source_url: source_url,
        metadata: metadata
      })
      assert source2.id == source1.id
      assert source2.last_seen_at > first_seen
    end

    test "create_event_source/3 merges metadata correctly", %{event: event, source: source} do
      source_url = "https://example.com/quiz"

      # Initial metadata
      {:ok, source1} = Events.create_event_source(%{
        event_id: event.id,
        source_id: source.id,
        source_url: source_url,
        metadata: %{"existing" => "value"}
      })

      # Add new metadata
      {:ok, source2} = Events.create_event_source(%{
        event_id: event.id,
        source_id: source.id,
        source_url: source_url,
        metadata: %{"new" => "value2"}
      })

      assert source2.id == source1.id
      assert source2.metadata == %{"existing" => "value", "new" => "value2"}
    end
  end

  describe "find_or_create_event/1" do
    setup do
      venue = TriviaAdvisor.LocationsFixtures.venue_fixture()
      %{venue: venue}
    end

    test "reuses existing event with same venue and day", %{venue: venue} do
      attrs = %{
        name: "Original Quiz",
        day_of_week: 2,
        start_time: ~T[19:00:00],
        frequency: "weekly",
        venue_id: venue.id
      }

      # Create initial event
      {:ok, event1} = Events.find_or_create_event(attrs)

      # Try to create/update with new name
      {:ok, event2} = Events.find_or_create_event(Map.put(attrs, :name, "Updated Quiz"))

      assert event2.id == event1.id
      assert event2.name == "Updated Quiz"
      assert event2.day_of_week == event1.day_of_week
    end

    test "creates new event for different day_of_week", %{venue: venue} do
      attrs = %{
        name: "Monday Quiz",
        day_of_week: 1,
        start_time: ~T[19:00:00],
        frequency: "weekly",
        entry_fee_cents: 42,
        venue_id: venue.id
      }

      # Create Monday event
      {:ok, monday_event} = Events.find_or_create_event(attrs)

      # Create Tuesday event
      {:ok, tuesday_event} = Events.find_or_create_event(Map.put(attrs, :day_of_week, 2))

      refute tuesday_event.id == monday_event.id
      assert tuesday_event.day_of_week == 2
      assert monday_event.day_of_week == 1
    end
  end
end

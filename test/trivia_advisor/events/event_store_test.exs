defmodule TriviaAdvisor.Events.EventStoreTest do
  use TriviaAdvisor.DataCase
  use ExUnit.Case

  alias TriviaAdvisor.Events.{Event, EventStore, Performer}
  alias TriviaAdvisor.Locations.{Country, City, Venue}
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Repo

  describe "process_event/3 with performer_id changes" do
    setup do
      # Set up test data - country, city, venue
      {:ok, country} = Repo.insert(%Country{
        code: "GB",
        name: "United Kingdom",
        slug: TriviaAdvisor.Utils.Slug.slugify("United Kingdom")
      })

      {:ok, city} = Repo.insert(%City{
        name: "London",
        country_id: country.id,
        slug: "london"
      })

      {:ok, venue} = Repo.insert(%Venue{
        name: "Test Pub",
        city_id: city.id,
        slug: "test-pub",
        address: "123 Test St",
        latitude: Decimal.new("51.5074"),
        longitude: Decimal.new("-0.1278")
      })

      # Create source
      {:ok, source} = Repo.insert(%Source{
        name: "Test Source",
        website_url: "https://example.com",
        slug: "test-source"
      })

      # Create two performers
      {:ok, performer_a} = Repo.insert(%Performer{
        name: "Performer A",
        source_id: source.id
      })

      {:ok, performer_b} = Repo.insert(%Performer{
        name: "Performer B",
        source_id: source.id
      })

      # Return the test data
      %{
        venue: venue,
        city: city,
        country: country,
        source: source,
        performer_a: performer_a,
        performer_b: performer_b
      }
    end

    test "updates only performer_id when it's the only field that changed", %{venue: venue, source: source, performer_a: performer_a, performer_b: performer_b} do
      # Ensure venue is properly preloaded
      venue = Repo.preload(venue, [city: :country])

      # Create event data with performer_a
      event_data = %{
        raw_title: "Test Quiz Night",
        name: "Test Quiz Night",
        day_of_week: 2, # Tuesday
        time_text: "Tuesday 19:00",
        start_time: ~T[19:00:00],
        frequency: :weekly,
        fee_text: "£5",
        description: "A fun quiz night",
        source_url: "https://example.com/test-quiz",
        performer_id: performer_a.id,
        hero_image_url: ""
      }

      # Process the event for the first time
      {:ok, {:ok, event}} = EventStore.process_event(venue, event_data, source.id)

      # Verify the event was created with performer_a
      assert event.performer_id == performer_a.id

      # Get the event's current updated_at timestamp
      event_before = Repo.get(Event, event.id)
      before_timestamp = event_before.updated_at

      # Wait to ensure timestamps would differ if updated
      # This is necessary because database timestamps may have limited precision
      Process.sleep(1000)

      # Now prepare the same event data but with performer_b
      updated_event_data = %{
        raw_title: "Test Quiz Night",
        name: "Test Quiz Night",
        day_of_week: 2, # Tuesday
        time_text: "Tuesday 19:00",
        start_time: ~T[19:00:00],
        frequency: :weekly,
        fee_text: "£5",
        description: "A fun quiz night",
        source_url: "https://example.com/test-quiz",
        performer_id: performer_b.id,
        hero_image_url: ""
      }

      # Process the event again with the new performer_id
      {:ok, {:ok, _updated_event}} = EventStore.process_event(venue, updated_event_data, source.id)

      # Fetch the fresh event from the database
      event_after = Repo.get(Event, event.id)

      # Verify performer_id was updated
      assert event_after.performer_id == performer_b.id

      # Verify updated_at was changed (proving a DB update occurred)
      assert DateTime.compare(event_after.updated_at, before_timestamp) == :gt

      # All other fields should remain unchanged
      assert event_after.name == event_before.name
      assert event_after.day_of_week == event_before.day_of_week
      assert event_after.start_time == event_before.start_time
      assert event_after.frequency == event_before.frequency
      assert event_after.entry_fee_cents == event_before.entry_fee_cents
      assert event_after.description == event_before.description
    end
  end
end

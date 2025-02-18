defmodule TriviaAdvisor.EventsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TriviaAdvisor.Events` context.
  """

  @doc """
  Generate a event.
  """
  def event_fixture(attrs \\ %{}) do
    venue = TriviaAdvisor.LocationsFixtures.venue_fixture()

    valid_attrs = %{
      name: "some event",
      day_of_week: 2,
      start_time: ~T[14:00:00],
      frequency: :weekly,
      entry_fee_cents: 42,
      description: "some description",
      venue_id: venue.id
    }

    {:ok, event} =
      attrs
      |> Enum.into(valid_attrs)
      |> TriviaAdvisor.Events.create_event()

    event
  end

  @doc """
  Generate a event_source.
  """
  def event_source_fixture(attrs \\ %{}) do
    event = event_fixture()
    source = TriviaAdvisor.ScrapingFixtures.source_fixture()
    unique_id = System.unique_integer([:positive])

    {:ok, event_source} =
      attrs
      |> Enum.into(%{
        status: "some status",
        metadata: %{},
        source_url: "some-source-url-#{unique_id}",
        last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
        event_id: event.id,
        source_id: source.id
      })
      |> TriviaAdvisor.Events.create_event_source()

    # Reload with associations for consistent test state
    TriviaAdvisor.Events.get_event_source!(event_source.id)
  end
end

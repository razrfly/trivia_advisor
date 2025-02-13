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

    {:ok, event} =
      attrs
      |> Enum.into(%{
        name: "some name",
        description: "some description",
        start_time: ~T[14:00:00],
        day_of_week: 42,
        frequency: :weekly,
        entry_fee_cents: 42,
        venue_id: venue.id
      })
      |> TriviaAdvisor.Events.create_event()

    event
  end

  @doc """
  Generate a event_source.
  """
  def event_source_fixture(attrs \\ %{}) do
    event = event_fixture()
    source = TriviaAdvisor.ScrapingFixtures.source_fixture()

    {:ok, event_source} =
      attrs
      |> Enum.into(%{
        status: "some status",
        metadata: %{},
        source_url: "some source_url",
        last_seen_at: ~U[2025-02-09 21:21:00Z],
        event_id: event.id,
        source_id: source.id
      })
      |> TriviaAdvisor.Events.create_event_source()

    # Reload with associations for consistent test state
    TriviaAdvisor.Events.get_event_source!(event_source.id)
  end
end

defmodule TriviaAdvisor.EventsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TriviaAdvisor.Events` context.
  """

  @doc """
  Generate a event.
  """
  def event_fixture(attrs \\ %{}) do
    {:ok, event} =
      attrs
      |> Enum.into(%{
        day_of_week: 42,
        description: "some description",
        entry_fee_cents: 42,
        frequency: 42,
        start_time: ~T[14:00:00],
        title: "some title"
      })
      |> TriviaAdvisor.Events.create_event()

    event
  end

  @doc """
  Generate a event_source.
  """
  def event_source_fixture(attrs \\ %{}) do
    {:ok, event_source} =
      attrs
      |> Enum.into(%{
        last_seen_at: ~U[2025-02-09 21:21:00Z],
        metadata: %{},
        source_url: "some source_url",
        status: "some status"
      })
      |> TriviaAdvisor.Events.create_event_source()

    event_source
  end
end

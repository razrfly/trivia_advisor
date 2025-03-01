defmodule TriviaAdvisor.Venues do
  @moduledoc """
  Utilities for working with venues.
  """

  alias TriviaAdvisor.Repo

  @doc """
  Preloads the venue association if it's not already loaded.

  Returns the original scope with the venue preloaded.
  """
  def maybe_preload_venue(scope) do
    case scope.venue do
      %Ecto.Association.NotLoaded{} ->
        # Reload venue if not loaded
        Repo.preload(scope, :venue)
      _loaded ->
        # Venue is already loaded
        scope
    end
  end
end

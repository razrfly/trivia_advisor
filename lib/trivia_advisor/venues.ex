defmodule TriviaAdvisor.Venues do
  @moduledoc """
  Utilities for working with venues.
  """

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.Venue

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

  @doc """
  Deletes a venue with proper cleanup of associated resources.

  This function ensures that image files are properly cleaned up
  by calling the before_delete callback before deleting the venue.

  ## Examples

      iex> delete_venue(venue)
      {:ok, %Venue{}}

      iex> delete_venue(venue)
      {:error, %Ecto.Changeset{}}

  """
  def delete_venue(%Venue{} = venue) do
    # First manually call the before_delete callback to clean up images
    Venue.before_delete(venue)

    # Then delete the venue
    Repo.delete(venue)
  end

  @doc """
  Deletes a venue by ID, with proper cleanup of associated resources.

  Returns {:ok, %Venue{}} on success, {:error, :not_found} if venue doesn't exist,
  or {:error, %Ecto.Changeset{}} on failure.
  """
  def delete_venue_by_id(id) when is_integer(id) or is_binary(id) do
    case Repo.get(Venue, id) do
      nil -> {:error, :not_found}
      venue -> delete_venue(venue)
    end
  end
end

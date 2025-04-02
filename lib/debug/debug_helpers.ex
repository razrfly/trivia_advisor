defmodule TriviaAdvisor.Debug.Helpers do
  @moduledoc """
  Helper functions for debugging and testing purposes.
  This module should not be used in production code.
  """

  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
  alias TriviaAdvisor.Locations.Venue

  @doc """
  Test function for InquizitionIndexJob to process a single venue.
  """
  def test_inquizition_venue(venue_name, venue_address) do
    # Find the venue in the database first, to make sure it exists
    venue_data = %{
      "name" => venue_name,
      "address" => venue_address,
      "time_text" => "",
      "phone" => nil,
      "website" => nil
    }

    # Get the Inquizition source
    source = Repo.get_by!(Source, name: "inquizition")

    Logger.info("🧪 Testing single venue processing for: #{venue_name}, #{venue_address}")

    # Process the single venue
    result = Scraper.process_single_venue(venue_data, source.id)

    # Return the result
    case result do
      [ok: venue] ->
        Logger.info("✅ Successfully processed test venue: #{venue.name}")
        {:ok, venue}
      nil ->
        Logger.error("❌ Failed to process test venue: #{venue_name}")
        {:error, :processing_failed}
      other ->
        Logger.error("❌ Unexpected result: #{inspect(other)}")
        {:error, :unexpected_result}
    end
  end

  @doc """
  Test function to find a venue by name and address.
  Reimplemented since the original test_find_venue was removed from InquizitionIndexJob.
  """
  def find_inquizition_venue(name, address) do
    # Implementation moved from InquizitionIndexJob.test_find_venue
    Logger.warning("⚠️ Using locally implemented venue finder - test_find_venue removed from InquizitionIndexJob")

    case find_venue_by_name_and_address(name, address) do
      nil -> {:error, :not_found}
      venue -> {:ok, venue}
    end
  end

  @doc """
  Test function to load existing sources.
  Reimplemented since the original test_load_existing_sources was removed from InquizitionIndexJob.
  """
  def load_inquizition_sources(_source_id) do
    Logger.warning("⚠️ test_load_existing_sources was removed from InquizitionIndexJob")
    Logger.warning("⚠️ Returning empty map as a compatibility fallback")

    # Return empty map for compatibility
    %{}
  end

  @doc """
  Test function to check if a venue should be processed.
  Reimplemented since the original test_should_process_venue? was removed from InquizitionIndexJob.
  """
  def should_process_inquizition_venue?(_venue, _existing_sources_by_venue) do
    Logger.warning("⚠️ test_should_process_venue? was removed from InquizitionIndexJob")
    Logger.warning("⚠️ Defaulting to process all venues (true)")

    # Default to processing all venues
    true
  end

  @doc """
  Test function to generate a venue key.
  Reimplemented since the original test_venue_key was removed from InquizitionIndexJob.
  """
  def generate_inquizition_venue_key(name, _address) do
    Logger.warning("⚠️ test_venue_key was removed from InquizitionIndexJob")

    # Simple implementation to normalize the name
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @doc """
  Run the full InquizitionIndexJob with optional arguments.
  """
  def run_inquizition_job(args \\ %{}) do
    InquizitionIndexJob.perform(%Oban.Job{args: args, id: 999999})
  end

  # Helper to find venue by name and address directly in the database
  defp find_venue_by_name_and_address(name, address) when is_binary(name) and is_binary(address) do
    # Normalize the name for more flexible matching
    normalized_name = name
                      |> String.downcase()
                      |> String.trim()

    # Try direct lookup first
    Repo.one(from v in Venue,
      where: v.name == ^name,
      limit: 1)
    || Repo.one(from v in Venue,
      where: fragment("LOWER(?) LIKE ?", v.name, ^"%#{normalized_name}%") and
             fragment("LOWER(?) LIKE ?", v.address, ^"%#{address}%"),
      limit: 1)
  end
  defp find_venue_by_name_and_address(_, _), do: nil
end

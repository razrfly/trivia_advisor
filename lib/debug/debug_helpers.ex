defmodule TriviaAdvisor.Debug.Helpers do
  @moduledoc """
  Helper functions for debugging and testing purposes.
  This module should not be used in production code.
  """

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
  alias TriviaAdvisor.Locations.Venue
  import Ecto.Query

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

    # Process the single venue directly
    # This replaces the call to removed test_single_venue function
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
  Find a venue by name and address - implementation reimplemented from the removed test function.
  """
  def find_inquizition_venue(name, address) do
    # Find venue by name and address directly
    if is_binary(name) and is_binary(address) do
      venue = Repo.one(from v in Venue,
        where: v.name == ^name and v.address == ^address,
        limit: 1)

      if venue, do: {:ok, venue}, else: {:error, :not_found}
    else
      {:error, :invalid_arguments}
    end
  end

  @doc """
  Generate a venue key from name and address - reimplemented from the removed test function.
  """
  def generate_inquizition_venue_key(name, address) do
    # Normalize name (remove parenthetical suffixes)
    name_without_suffix = name
                      |> String.replace(~r/\s*\([^)]+\)\s*$/, "")
                      |> String.trim()

    normalized_name = name_without_suffix
                  |> String.downcase()
                  |> String.trim()

    normalized_address = address
                       |> String.downcase()
                       |> String.replace(~r/\s+/, " ")
                       |> String.trim()

    "#{normalized_name}|#{normalized_address}"
  end

  # The following functions are commented out as they would need more complex reimplementation
  # and might not be worth the effort since they're only used for debugging

  # @doc """
  # Load existing sources - commented out as it would need complex reimplementation.
  # """
  # def load_inquizition_sources(_source_id) do
  #   Logger.warning("load_inquizition_sources is no longer available")
  #   %{}
  # end

  # @doc """
  # Check if a venue should be processed - commented out as it would need complex reimplementation.
  # """
  # def should_process_inquizition_venue?(_venue, _existing_sources_by_venue) do
  #   Logger.warning("should_process_inquizition_venue? is no longer available")
  #   true
  # end

  @doc """
  Run the full InquizitionIndexJob with optional arguments.
  """
  def run_inquizition_job(args \\ %{}) do
    InquizitionIndexJob.perform(%Oban.Job{args: args, id: 999999})
  end
end

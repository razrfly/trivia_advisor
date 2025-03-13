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
  Test function to find a venue by name and address using InquizitionIndexJob's venue lookup logic.
  """
  def find_inquizition_venue(name, address) do
    InquizitionIndexJob.test_find_venue(name, address)
  end

  @doc """
  Test function to load existing sources using InquizitionIndexJob's logic.
  """
  def load_inquizition_sources(source_id) do
    InquizitionIndexJob.test_load_existing_sources(source_id)
  end

  @doc """
  Test function to check if a venue should be processed using InquizitionIndexJob's logic.
  """
  def should_process_inquizition_venue?(venue, existing_sources_by_venue) do
    InquizitionIndexJob.test_should_process_venue?(venue, existing_sources_by_venue)
  end

  @doc """
  Test function to generate a venue key using InquizitionIndexJob's logic.
  """
  def generate_inquizition_venue_key(name, address) do
    InquizitionIndexJob.test_venue_key(name, address)
  end

  @doc """
  Run the full InquizitionIndexJob with optional arguments.
  """
  def run_inquizition_job(args \\ %{}) do
    InquizitionIndexJob.perform(%Oban.Job{args: args, id: 999999})
  end
end

defmodule TriviaAdvisor.Scraping.TestVenueProcessing do
  @moduledoc """
  Helper module for testing venue processing without running the full job.
  """

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Oban.InquizitionDetailJob
  alias TriviaAdvisor.Scraping.RateLimiter

  @doc """
  Process a single test venue to verify the processing chain works correctly.
  """
  def test_single_venue do
    # Get the Inquizition source
    source = Repo.get_by!(Source, name: "inquizition")
    Logger.info("Source: #{inspect(source)}")

    # Create a test venue - using The Railway as a test case
    # since it's one we've seen issues with
    test_venue = %{
      "name" => "The Railway",
      "address" => "Railway Road, Chadderton, Oldham, OL9 7LG",
      "time_text" => "Tuesdays, 8:30pm",
      "phone" => "0161 624 1301",
      "website" => nil
    }

    Logger.info("🧪 Testing venue processing with venue: #{test_venue["name"]}")
    Logger.info("Test venue data: #{inspect(test_venue)}")

    # First, parse the venue (step 1)
    parsed_venue = try do
      Logger.info("Step 1: Parsing venue")
      result = Scraper.parse_venue_data(test_venue)
      Logger.info("Parsed venue: #{inspect(result)}")
      result
    rescue
      e ->
        Logger.error("❌ Error in parse_venue_data: #{inspect(e)}")
        nil
    end

    # If parsing succeeds, try processing the venue (step 2)
    case parsed_venue do
      nil ->
        Logger.error("❌ Venue parsing failed")
        {:error, :parsing_failed}

      venue ->
        Logger.info("Step 2: Processing venue")
        try do
          # Call process_venue_and_create_event directly for testing
          result = Scraper.process_venue_with_raw_data(venue, test_venue, source.id)
          Logger.info("Venue processing result: #{inspect(result)}")
          result
        rescue
          e ->
            stack = __STACKTRACE__
            Logger.error("❌ Error in process_venue_with_raw_data: #{inspect(e)}")
            Logger.error("Stack trace: #{inspect(stack)}")
            {:error, "Processing error: #{Exception.message(e)}"}
        end
    end
  end

  # Make the function public for testing
  def process_venue_with_raw_data(venue, venue_data, source_id) do
    Scraper.process_venue_with_raw_data(venue, venue_data, source_id)
  end
end

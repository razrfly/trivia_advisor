defmodule TriviaAdvisor.Scraping.TestVenueProcessing do
  @moduledoc """
  Helper module for testing venue processing without running the full job.
  """

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper
  alias TriviaAdvisor.Scraping.Source

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

    # Use the public process_single_venue function instead of the private ones
    Logger.info("Processing venue...")
    result = Scraper.process_single_venue(test_venue, source.id)
    Logger.info("Processing result: #{inspect(result)}")

    result
  end
end

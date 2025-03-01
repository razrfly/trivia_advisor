require Logger

# Test extraction for The Molecule Effect
venue_id = "venue_7541"
url = "https://www.geekswhodrink.com/venues/#{venue_id}/"

Logger.configure(level: :debug)

IO.puts("\n📋 Testing extraction for venue: #{url}")

# Get the HTML
case HTTPoison.get(url) do
  {:ok, %{status_code: 200, body: html}} ->
    IO.puts("\n✅ Successfully fetched HTML")

    # Parse the document
    {:ok, document} = Floki.parse_document(html)

    # Extract time from the document
    IO.puts("\n⏰ EXTRACTING TIME FROM DOCUMENT:")

    time_element = Floki.find(document, ".venueHero__time .time-moment")
    IO.puts("Time element: #{inspect(time_element)}")

    visible_time = Floki.text(time_element) |> String.trim()
    IO.puts("Visible time text: #{inspect(visible_time)}")

    data_time = Floki.attribute(time_element, "data-time") |> List.first()
    IO.puts("Data-time attribute: #{inspect(data_time)}")

    # Call our extractor
    IO.puts("\n⏰ USING VENUE DETAILS EXTRACTOR:")
    details = TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.VenueDetailsExtractor.extract_additional_details(url)
    IO.inspect(details, label: "Extracted details")

  other ->
    IO.puts("Failed to fetch HTML: #{inspect(other)}")
end

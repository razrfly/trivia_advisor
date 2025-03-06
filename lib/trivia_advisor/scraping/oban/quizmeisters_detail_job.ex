defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Scrapers.Quizmeisters.VenueExtractor
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.{EventStore, Performer}
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue" => venue_data, "source_id" => source_id}}) do
    Logger.info("🔄 Processing venue: #{venue_data["name"]}")
    source = Repo.get!(Source, source_id)

    # Process the venue and event using existing code patterns
    case process_venue(venue_data, source) do
      {:ok, %{venue: venue, event: {:ok, event_struct}}} ->
        # Handle the case where event is a tuple
        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event_struct.id}}

      {:ok, %{venue: venue, event: event}} ->
        # Handle the case where event is already unwrapped
        Logger.info("✅ Successfully processed venue: #{venue.name}")
        {:ok, %{venue_id: venue.id, event_id: event.id}}

      {:error, reason} ->
        Logger.error("❌ Failed to process venue: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Process venue - adapted from Quizmeisters scraper
  defp process_venue(location, source) do
    # First, parse the venue data (similar to parse_venue in original scraper)
    time_text = get_trivia_time(location)

    # If time_text is empty, try to find the day from fields
    time_text = if time_text == "" do
      find_trivia_day_from_fields(location)
    else
      time_text
    end

    # If we still can't determine a day/time, use a default value
    time_text = if time_text == "" do
      Logger.warning("⚠️ No trivia day/time found for venue: #{location["name"]}. Attempting to proceed with defaults.")
      # Default to Thursday 7:00 PM as a fallback to allow processing
      "Thursday 7:00 PM"
    else
      time_text
    end

    case TimeParser.parse_time_text(time_text) do
      {:ok, %{day_of_week: day_of_week, start_time: start_time}} ->
        # Build the venue data for processing
        venue_data = %{
          raw_title: location["name"],
          title: location["name"],
          name: location["name"],
          address: location["address"],
          time_text: time_text,
          day_of_week: day_of_week,
          start_time: start_time,
          frequency: :weekly,
          fee_text: "Free", # All Quizmeisters events are free
          phone: location["phone"],
          website: nil, # Will be fetched from individual venue page
          description: nil, # Will be fetched from individual venue page
          hero_image: nil,
          hero_image_url: nil, # Will be fetched from individual venue page
          url: location["url"],
          facebook: nil, # Will be fetched from individual venue page
          instagram: nil, # Will be fetched from individual venue page
          latitude: location["lat"],
          longitude: location["lng"],
          postcode: location["postcode"]
        }

        # Log venue details
        VenueHelpers.log_venue_details(venue_data)

        # Fetch venue details from the venue page
        case fetch_venue_details(venue_data, source) do
          {:ok, result} ->
            {:ok, result}
          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to parse time text: #{reason} for #{location["name"]}")
        Logger.error("Time text was: '#{time_text}'")
        {:error, reason}
    end
  end

  # Extract trivia time from location data - improved to better handle missing data
  defp get_trivia_time(%{"custom_fields" => custom_fields}) when is_map(custom_fields) do
    case Map.get(custom_fields, "trivia_night") do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _ -> ""
    end
  end
  defp get_trivia_time(_), do: ""

  # Try to find trivia day from fields array
  defp find_trivia_day_from_fields(%{"fields" => fields}) when is_list(fields) do
    # Look for a field that might contain day information
    trivia_field = Enum.find(fields, fn field ->
      name = Map.get(field, "name", "")
      value = Map.get(field, "value", "")

      is_binary(name) and is_binary(value) and
      (String.contains?(String.downcase(name), "trivia") or
       String.contains?(String.downcase(name), "quiz"))
    end)

    case trivia_field do
      %{"value" => value} when is_binary(value) and byte_size(value) > 0 -> value
      _ -> ""
    end
  end
  defp find_trivia_day_from_fields(_), do: ""

  # Fetch venue details - adapted from Quizmeisters scraper
  defp fetch_venue_details(venue_data, source) do
    Logger.info("Processing venue: #{venue_data.title}")

    case HTTPoison.get(venue_data.url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, document} <- Floki.parse_document(body),
             {:ok, extracted_data} <- VenueExtractor.extract_venue_data(document, venue_data.url, venue_data.raw_title) do

          # First merge the extracted data with the API data
          merged_data = Map.merge(venue_data, extracted_data)

          # Then process through VenueStore with social media data
          venue_store_data = %{
            name: merged_data.name,
            address: merged_data.address,
            phone: merged_data.phone,
            website: merged_data.website,
            facebook: merged_data.facebook,
            instagram: merged_data.instagram,
            latitude: merged_data.latitude,
            longitude: merged_data.longitude,
            postcode: merged_data.postcode
          }

          case VenueStore.process_venue(venue_store_data) do
            {:ok, venue} ->
              final_data = Map.put(merged_data, :venue_id, venue.id)
              VenueHelpers.log_venue_details(final_data)

              # Process performer if present
              performer_id = case final_data.performer do
                %{name: name, profile_image: image_url} when not is_nil(name) and is_binary(image_url) and image_url != "" ->
                  # Download the image directly
                  profile_image = ImageDownloader.download_performer_image(image_url)

                  case Performer.find_or_create(%{
                    name: name,
                    profile_image: profile_image,
                    source_id: source.id
                  }) do
                    {:ok, performer} -> performer.id
                    _ -> nil
                  end
                _ -> nil
              end

              # Process the event using EventStore like QuestionOne
              event_data = %{
                raw_title: final_data.raw_title,
                name: venue.name,
                time_text: format_time_text(final_data.day_of_week, final_data.start_time),
                description: final_data.description,
                fee_text: "Free", # All Quizmeisters events are free
                hero_image_url: final_data.hero_image_url,
                source_url: venue_data.url,
                performer_id: performer_id
              }

              # Handle the double-wrapped tuple from process_event
              case EventStore.process_event(venue, event_data, source.id) do
                {:ok, event} ->
                  Logger.info("✅ Successfully processed event for venue: #{venue.name}")
                  {:ok, %{venue: venue, event: event}}
                {:error, reason} ->
                  Logger.error("❌ Failed to process event: #{inspect(reason)}")
                  {:error, reason}
              end

            error ->
              Logger.error("Failed to process venue: #{inspect(error)}")
              {:error, error}
          end
        else
          {:error, reason} ->
            Logger.error("Failed to extract venue data: #{reason}")
            {:error, reason}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("HTTP #{status} when fetching venue: #{venue_data.url}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("Error fetching venue #{venue_data.url}: #{inspect(error)}")
        {:error, error}
    end
  end

  # Format time text - adapted from Quizmeisters scraper
  defp format_time_text(day_of_week, start_time) do
    day_name = case day_of_week do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> ""
    end

    "#{day_name} #{start_time}"
  end
end

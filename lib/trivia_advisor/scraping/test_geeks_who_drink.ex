defmodule TriviaAdvisor.Scraping.TestGeeksWhoDrink do
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Scraping.Helpers.{TimeParser, VenueHelpers}
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.Events.EventStore
  alias HtmlEntities

  def run do
    Logger.info("🧪 Running GeeksWhoDrink test...")

    # Get the source record
    source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

    # Create a test venue
    venue_data = %{
      "title" => "Test Venue",
      "address" => "123 Test St, Denver, CO 80202",
      "time_text" => "Tuesdays at",
      "source_url" => "https://www.geekswhodrink.com/venues/test",
      "logo_url" => "https://example.com/logo.png",
      "url" => "https://www.geekswhodrink.com/venues/test"
    }

    # Manually process the venue similar to what GeeksWhoDrinkDetailJob.process_venue does
    try do
      # Create additional details manually
      additional_details = %{
        start_time: "19:00",
        description: "Test description",
        phone: "555-123-4567",
        website: "https://example.com",
        facebook: nil,
        instagram: nil,
        fee_text: "Free"
      }

      # Decode HTML entities from title
      clean_title = HtmlEntities.decode(venue_data["title"])

      # Parse day of week from time_text
      day_of_week = case venue_data["time_text"] do
        time_text when is_binary(time_text) and byte_size(time_text) > 3 ->
          case TimeParser.parse_day_of_week(time_text) do
            {:ok, day} -> day
            _ -> 2  # Default to Tuesday (2) if parsing fails
          end
        _ -> 2  # Default to Tuesday if time_text is invalid
      end

      # Create venue data map
      venue_data_map = %{
        raw_title: venue_data["title"],
        title: clean_title,
        address: venue_data["address"],
        time_text: venue_data["time_text"],
        url: venue_data["url"],
        hero_image_url: venue_data["logo_url"],
        day_of_week: day_of_week,
        frequency: :weekly
      }

      # Merge with additional details
      merged_data = Map.merge(venue_data_map, additional_details)
      |> tap(&VenueHelpers.log_venue_details/1)

      # Prepare data for VenueStore
      venue_attrs = %{
        name: clean_title,
        address: merged_data.address,
        phone: Map.get(merged_data, :phone, nil),
        website: Map.get(merged_data, :website, nil),
        facebook: Map.get(merged_data, :facebook, nil),
        instagram: Map.get(merged_data, :instagram, nil),
        hero_image_url: Map.get(merged_data, :hero_image_url, nil)
      }

      Logger.info("""
      🏢 Processing venue through VenueStore:
        Name: #{venue_attrs.name}
        Address: #{venue_attrs.address}
        Website: #{venue_attrs.website}
      """)

      case VenueStore.process_venue(venue_attrs) do
        {:ok, venue} ->
          Logger.info("✅ Successfully processed venue: #{venue.name}")

          # Format day and time
          day_name = case day_of_week do
            1 -> "Monday"
            2 -> "Tuesday"
            3 -> "Wednesday"
            4 -> "Thursday"
            5 -> "Friday"
            6 -> "Saturday"
            7 -> "Sunday"
            _ -> "Tuesday" # Fallback
          end

          time = additional_details.start_time
          formatted_time = "#{day_name} #{time}"

          # Create event data
          event_data = %{
            raw_title: "Geeks Who Drink at #{venue.name}",
            name: venue.name,
            time_text: formatted_time,
            description: Map.get(merged_data, :description, ""),
            fee_text: "Free", # Explicitly set as free for all GWD events
            source_url: venue_data["url"],
            performer_id: nil,
            hero_image_url: venue_data["logo_url"]
          }

          case EventStore.process_event(venue, event_data, source.id) do
            {:ok, event} ->
              Logger.info("✅ Successfully created event for venue: #{venue.name}")
              {:ok, {venue, event}}
            {:error, reason} ->
              Logger.error("❌ Failed to create event: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("❌ Failed to process venue: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("""
        ❌ Failed to process venue
        Error: #{Exception.message(e)}
        Venue Data: #{inspect(venue_data)}
        """)
        {:error, e}
    end
  end
end

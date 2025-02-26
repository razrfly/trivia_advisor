defmodule TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.Scraper do
  require Logger
  alias TriviaAdvisor.Scraping.Helpers.VenueHelpers
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.{NonceExtractor, VenueExtractor, VenueDetailsExtractor}
  alias TriviaAdvisor.{Repo, Locations.VenueStore}
  alias TriviaAdvisor.Scraping.{Source, ScrapeLog}
  alias TriviaAdvisor.Events.EventStore
  alias HtmlEntities

  @base_url "https://www.geekswhodrink.com/wp-admin/admin-ajax.php"
  @base_params %{
    "action" => "mb_display_mapped_events",
    "bounds[northLat]" => "71.35817123219137",
    "bounds[southLat]" => "-2.63233642366575",
    "bounds[westLong]" => "-174.787181",
    "bounds[eastLong]" => "-32.75593100000001",
    "days" => "",
    "brands" => "",
    "search" => "",
    "startLat" => "44.967243",
    "startLong" => "-103.771556",
    "searchInit" => "true",
    "tlCoord" => "",
    "brCoord" => "",
    "tlMapCoord" => "[-174.787181, 71.35817123219137]",
    "brMapCoord" => "[-32.75593100000001, -2.63233642366575]",
    "hasAll" => "true"
  }

  def run do
    Logger.info("Starting Geeks Who Drink scraper...")
    source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

    case ScrapeLog.create_log(source) do
      {:ok, log} ->
        try do
          Logger.info("🔍 Fetching GeeksWhoDrink venues...")

          with {:ok, nonce} <- NonceExtractor.fetch_nonce(),
               {:ok, venues} <- fetch_venues(nonce) do

            # Process each venue through VenueStore
            detailed_venues = venues
            |> Enum.map(&process_venue/1)
            |> Enum.reject(&is_nil/1)

            venue_count = length(detailed_venues)
            Logger.info("✅ Successfully scraped #{venue_count} venues")

            # Convert venues to simple maps for JSON encoding
            venue_maps = Enum.map(detailed_venues, fn {venue, _} ->
              %{
                id: venue.id,
                name: venue.name,
                address: venue.address,
                postcode: venue.postcode,
                phone: venue.phone,
                website: venue.website
              }
            end)

            ScrapeLog.update_log(log, %{
              success: true,
              event_count: venue_count,
              metadata: %{
                total_venues: venue_count,
                venues: venue_maps,
                completed_at: DateTime.utc_now()
              }
            })

            {:ok, detailed_venues}
          else
            {:error, reason} ->
              Logger.error("❌ Failed to fetch venues: #{inspect(reason)}")
              ScrapeLog.log_error(log, reason)
              {:error, reason}
          end
        rescue
          e ->
            Logger.error("❌ Scraper failed: #{Exception.message(e)}")
            ScrapeLog.log_error(log, e)
            {:error, e}
        end

      {:error, reason} ->
        Logger.error("Failed to create scrape log: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_venue(venue_data) do
    try do
      # Get additional details from venue page
      additional_details =
        case VenueDetailsExtractor.extract_additional_details(venue_data.source_url) do
          {:ok, details} -> details
          _ -> %{}
        end

      # Merge venue data with additional details
      venue_data = Map.merge(venue_data, additional_details)
      |> tap(&VenueHelpers.log_venue_details/1)

      # Extract clean title
      clean_title = HtmlEntities.decode(venue_data.title)

      # Prepare data for VenueStore - ensure we have complete address for Google lookup
      venue_attrs = %{
        name: clean_title,
        address: venue_data.address,  # This should be the full address including city and state
        phone: venue_data.phone,
        website: venue_data.website,
        facebook: venue_data.facebook,
        instagram: venue_data.instagram,
        hero_image_url: venue_data.hero_image_url
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

          # Get source for event creation
          source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

          # Create event data
          event_data = %{
            raw_title: "Geeks Who Drink at #{venue.name}",
            name: venue.name,
            time_text: "Tuesday 20:00",  # Format as "Day HH:MM" which EventStore expects
            description: venue_data.description,
            fee_text: "Free",  # Explicitly set as free for all GWD events
            source_url: venue_data.url,
            performer_id: nil,  # GWD doesn't provide performer info
            hero_image_url: venue_data.hero_image_url  # Pass through unchanged
          }

          case EventStore.process_event(venue, event_data, source.id) do
            {:ok, _event} ->
              Logger.info("✅ Successfully created event for venue: #{venue.name}")
              {venue, venue_data}
            {:error, reason} ->
              Logger.error("❌ Failed to create event: #{inspect(reason)}")
              nil
          end

        {:error, reason} ->
          Logger.error("❌ Failed to process venue: #{inspect(reason)}")
          nil
      end
    rescue
      e ->
        Logger.error("""
        ❌ Failed to process venue
        Error: #{Exception.message(e)}
        Venue Data: #{inspect(venue_data)}
        """)
        nil
    end
  end

  defp fetch_venues(nonce) do
    query_params = Map.put(@base_params, "nonce", nonce)
    url = @base_url <> "?" <> URI.encode_query(query_params)

    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        venues = parse_response(body)
        {:ok, venues}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP request failed with status #{status}"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp parse_response(body) do
    String.split(body, "<a id=\"quizBlock-")
    |> Enum.drop(1) # Drop the first empty element
    |> Enum.map(fn block ->
      "<a id=\"quizBlock-" <> block
    end)
    |> Enum.map(&extract_venue_info/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_venue_info(block) do
    Logger.debug("Processing HTML block: #{inspect(block)}")
    case VenueExtractor.extract_venue_data(block) do
      {:ok, venue_data} ->
        raw_title = venue_data.title
        clean_title = HtmlEntities.decode(venue_data.title)

        # Parse time text for day of week
        day_of_week =
          with time_text when is_binary(time_text) and byte_size(time_text) > 3 <- venue_data.time_text,
               {:ok, parsed} <- TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time_text(time_text) do
            parsed.day_of_week
          else
            _ -> nil
          end

        # Get additional details from venue page
        additional_details =
          case VenueDetailsExtractor.extract_additional_details(venue_data.source_url) do
            {:ok, details} -> details
            _ -> %{}
          end

        # Build complete venue data
        venue_data = %{
          raw_title: raw_title,
          title: clean_title,
          address: venue_data.address,
          time_text: venue_data.time_text,
          day_of_week: day_of_week || "",
          start_time: additional_details.start_time,
          frequency: :weekly,
          fee_text: additional_details.fee_text,
          phone: additional_details.phone,
          website: additional_details.website,
          description: additional_details.description,
          hero_image_url: venue_data.logo_url,  # Use original URL without modification
          url: venue_data.source_url,
          facebook: additional_details.facebook,
          instagram: additional_details.instagram
        }
        |> tap(&VenueHelpers.log_venue_details/1)

        # Process through VenueStore
        venue_attrs = %{
          name: clean_title,
          address: venue_data.address,
          phone: venue_data.phone,
          website: venue_data.website,
          facebook: venue_data.facebook,
          instagram: venue_data.instagram,
          hero_image_url: venue_data.hero_image_url
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

            # Get source for event creation
            source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

            # Create event data
            event_data = %{
              raw_title: "Geeks Who Drink at #{venue.name}",
              name: venue.name,
              time_text: "Tuesday 20:00",  # Format as "Day HH:MM" which EventStore expects
              description: venue_data.description,
              fee_text: "Free",  # Explicitly set as free for all GWD events
              source_url: venue_data.url,
              performer_id: nil,
              hero_image_url: venue_data.hero_image_url  # Pass through unchanged
            }

            case EventStore.process_event(venue, event_data, source.id) do
              {:ok, _event} ->
                Logger.info("✅ Successfully created event for venue: #{venue.name}")
                {venue, venue_data}
              {:error, reason} ->
                Logger.error("❌ Failed to create event: #{inspect(reason)}")
                nil
            end

          {:error, reason} ->
            Logger.error("❌ Failed to process venue: #{inspect(reason)}")
            nil
        end

      _ ->
        Logger.warning("Failed to extract venue info from block")
        nil
    end
  end
end

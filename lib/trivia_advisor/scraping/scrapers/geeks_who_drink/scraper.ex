defmodule TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.Scraper do
  @moduledoc """
  DEPRECATED: This legacy scraper is deprecated in favor of Oban jobs.
  Please use TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob instead.
  """

  require Logger
  alias TriviaAdvisor.Scraping.Helpers.VenueHelpers
  alias TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.{NonceExtractor, VenueExtractor, VenueDetailsExtractor}
  alias TriviaAdvisor.{Repo, Locations.VenueStore}
  alias TriviaAdvisor.Scraping.Source
  alias TriviaAdvisor.Events.EventStore
  alias TriviaAdvisor.Services.GooglePlaceImageStore
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

  @doc """
  Main entry point for the scraper.

  DEPRECATED: Please use TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob instead.
  """
  def run do
    Logger.warning("⚠️ DEPRECATED: This legacy scraper is deprecated. Please use TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob instead.")
    Logger.info("Starting Geeks Who Drink scraper...")
    _source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")
    start_time = DateTime.utc_now()

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
        _venue_maps = Enum.map(detailed_venues, fn {venue, _} ->
          %{
            id: venue.id,
            name: venue.name,
            address: venue.address,
            postcode: venue.postcode,
            phone: venue.phone,
            website: venue.website
          }
        end)

        # Log summary of scrape results
        Logger.info("""
        📊 Geeks Who Drink Scrape Summary:
        - Total venues: #{venue_count}
        - Started at: #{DateTime.to_iso8601(start_time)}
        - Completed at: #{DateTime.to_iso8601(DateTime.utc_now())}
        """)

        {:ok, detailed_venues}
      else
        {:error, reason} ->
          Logger.error("❌ Failed to fetch venues: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("❌ Scraper failed: #{Exception.message(e)}")
        {:error, e}
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

          # Check if we should fetch Google Place images using the centralized function
          venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

          # Get source for event creation
          source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

          # Format day and time from the extracted details
          time_text = format_event_time(venue_data, additional_details)

          # Create event data
          event_data = %{
            raw_title: "Geeks Who Drink at #{venue.name}",
            name: venue.name,
            time_text: time_text,  # Use formatted time text
            description: venue_data.description,
            fee_text: "Free",  # Explicitly set as free for all GWD events
            source_url: venue_data.url,
            performer_id: get_performer_id(source.id, additional_details),  # Try to get performer ID
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

  defp format_event_time(venue_data, additional_details) do
    # Log inputs for debugging
    Logger.debug("""
    📅 Format Event Time:
      venue_data.time_text: #{inspect(venue_data.time_text)}
      venue_data.day_of_week: #{inspect(venue_data.day_of_week)}
      additional_details.start_time: #{inspect(additional_details.start_time)}
    """)

    # Extract day of week from venue data if available
    day_name = case venue_data.time_text do
      time_text when is_binary(time_text) and byte_size(time_text) > 3 ->
        case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_day_of_week(time_text) do
          {:ok, day_of_week} ->
            day_to_string(day_of_week)
          _ ->
            # Default to Tuesday if day extraction fails
            "Tuesday"
        end
      _ ->
        # Default day
        "Tuesday"
    end

    # Extract time from additional details if available
    time = cond do
      # If start_time is available as a formatted string
      is_binary(additional_details.start_time) && String.match?(additional_details.start_time, ~r/\d{2}:\d{2}/) ->
        Logger.debug("📅 Using start_time from additional_details: #{additional_details.start_time}")
        additional_details.start_time

      # If we can extract time from the venue time_text
      is_binary(venue_data.time_text) and byte_size(venue_data.time_text) > 3 ->
        Logger.debug("📅 Attempting to parse time from venue_data.time_text: #{venue_data.time_text}")
        case TriviaAdvisor.Scraping.Helpers.TimeParser.parse_time(venue_data.time_text) do
          {:ok, time_str} ->
            Logger.debug("📅 Successfully parsed time: #{time_str}")
            time_str
          _ ->
            Logger.debug("📅 Failed to parse time, using default")
            "20:00"  # Default time
        end

      # Default fallback
      true ->
        Logger.debug("📅 No valid time source found, using default time")
        "20:00"
    end

    # Format: "Day HH:MM"
    formatted_time = "#{day_name} #{time}"
    Logger.debug("📅 Final formatted time: #{formatted_time}")
    formatted_time
  end

  defp day_to_string(day_of_week) do
    case day_of_week do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Tuesday" # Fallback
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

            # Check if we should fetch Google Place images using the centralized function
            venue = GooglePlaceImageStore.maybe_update_venue_images(venue)

            # Get source for event creation
            source = Repo.get_by!(Source, website_url: "https://www.geekswhodrink.com")

            # Format the event time correctly
            time_text = format_event_time(venue_data, additional_details)

            # Create event data with the correct time info
            event_data = %{
              raw_title: "Geeks Who Drink at #{venue.name}",
              name: venue.name,
              time_text: time_text,
              description: venue_data.description,
              fee_text: "Free",  # Explicitly set as free for all GWD events
              source_url: venue_data.url,
              performer_id: get_performer_id(source.id, additional_details),  # Try to get performer ID
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

  defp get_performer_id(source_id, additional_details) do
    # Check if there's performer data in the additional details
    case Map.get(additional_details, :performer) do
      %{name: name, profile_image: image_url} when not is_nil(name) and not is_nil(image_url) ->
        Logger.info("🎭 Found performer: #{name} with image: #{image_url}")

        # Download the profile image
        profile_image = case TriviaAdvisor.Scraping.Helpers.ImageDownloader.download_performer_image(image_url) do
          %Plug.Upload{filename: filename, path: path} = image_data when not is_nil(path) ->
            Logger.info("✅ Downloaded performer image to: #{path}, filename: #{filename}")

            # Verify the file exists and is not empty
            case File.stat(path) do
              {:ok, %{size: size}} when size > 0 ->
                Logger.info("✅ Image file exists and has size: #{size} bytes")
                image_data
              {:ok, %{size: 0}} ->
                Logger.warning("⚠️ Downloaded image file is empty, using nil")
                nil
              {:error, reason} ->
                Logger.warning("⚠️ Can't verify downloaded image: #{inspect(reason)}, trying anyway")
                image_data
            end

          nil ->
            Logger.error("❌ Failed to download performer image")
            nil
        end

        # Log the profile_image structure we're passing to find_or_create
        Logger.debug("🖼️ Profile image data being passed to find_or_create: #{inspect(profile_image)}")

        # Create or update the performer
        case TriviaAdvisor.Events.Performer.find_or_create(%{
          name: name,
          profile_image: profile_image,
          source_id: source_id
        }) do
          {:ok, performer} ->
            Logger.info("✅ Created/updated performer: #{name}, ID: #{performer.id}, profile_image: #{inspect(performer.profile_image)}")
            performer.id
          {:error, changeset} ->
            Logger.error("❌ Failed to create performer: #{inspect(changeset.errors)}")
            # Log the full changeset for debugging
            Logger.debug("🔍 Full changeset: #{inspect(changeset)}")
            nil
        end

      # Handle different error formats gracefully
      {:error, reason} ->
        Logger.info("🚫 No performer data available: #{reason}")
        nil

      _ ->
        Logger.debug("🔍 No performer data found in additional details")
        nil
    end
  end
end

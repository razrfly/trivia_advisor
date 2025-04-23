defmodule TriviaAdvisorWeb.Live.Venue.Helpers.VenueShowHelpers do
  @moduledoc """
  Helper functions for the Venue Show LiveView.
  """
  alias TriviaAdvisor.Locations
  require Logger

  # Helper functions
  def get_venue_by_slug(slug) do
    try do
      # Try to get venue from database using slug
      venue = Locations.get_venue_by_slug(slug)
      |> Locations.load_venue_relations()
      |> TriviaAdvisor.Repo.preload(city: :country)

      if venue do
        {:ok, venue}
      else
        {:error, :not_found}
      end
    rescue
      e ->
        Logger.error("Failed to get venue: #{inspect(e)}")
        {:error, :not_found}
    end
  end

  # Helper to get day of week from venue events
  def get_day_of_week(venue) do
    # Get the day of week from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :day_of_week)
    else
      # Default value if no events
      1 # Monday as default
    end
  end

  # Helper to get start time from venue events
  def get_start_time(venue) do
    # Get the start time from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :start_time)
    else
      # Default value if no events
      "7:00 PM"
    end
  end

  def format_next_date(day_of_week) when is_integer(day_of_week) do
    today = Date.utc_today()
    today_day = Date.day_of_week(today)

    # Calculate days until the next occurrence
    days_until = if day_of_week >= today_day do
      day_of_week - today_day
    else
      7 - today_day + day_of_week
    end

    # Get the date of the next occurrence
    next_date = Date.add(today, days_until)

    # Format as "Month Day" (e.g., "May 15")
    month = case next_date.month do
      1 -> "Jan"
      2 -> "Feb"
      3 -> "Mar"
      4 -> "Apr"
      5 -> "May"
      6 -> "Jun"
      7 -> "Jul"
      8 -> "Aug"
      9 -> "Sep"
      10 -> "Oct"
      11 -> "Nov"
      12 -> "Dec"
    end

    "#{month} #{next_date.day}"
  end

  def format_next_date(_), do: "TBA"

  # Helper to get reviews from venue or return empty list if they don't exist
  def get_venue_reviews(venue) do
    # Return empty list if venue has no reviews field
    Map.get(venue, :reviews, [])
  end

  # Get venue image - updated to use the new ImageUrlHelper
  def get_venue_image(venue) do
    # Use the enhanced ImageHelpers implementation that provides Unsplash fallbacks
    TriviaAdvisorWeb.Helpers.ImageHelpers.get_venue_image(venue)
  end

  # Helper to get entry fee cents from venue events
  def get_entry_fee_cents(venue) do
    # Get the entry fee from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :entry_fee_cents)
    else
      nil # Free by default
    end
  end

  # Helper to get frequency from venue events
  def get_frequency(venue) do
    # Get the frequency from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :frequency, "Weekly") # Default to weekly if not found
    else
      "Weekly" # Default value if no events
    end
  end

  # Helper to get description from venue events
  def get_venue_description(venue) do
    # Get the description from the first event if available
    if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      Map.get(event, :description, "No description available.") # Default message if not found
    else
      # If no events, check if description is in metadata
      venue.metadata["description"] || "No description available for this trivia night."
    end
  end

  # Get nearby venues
  def get_nearby_venues(venue, limit) do
    if venue.latitude && venue.longitude do
      # Convert Decimal values to floats
      lat = to_float(venue.latitude)
      lng = to_float(venue.longitude)

      coords = {lat, lng}

      # Find nearby venues
      nearby_venues = TriviaAdvisor.Locations.find_venues_near_coordinates(coords,
        radius_km: 25,
        limit: limit + 1, # Get one extra to filter out the current venue
        load_relations: true
      )

      # Filter out the current venue and limit to specified number
      nearby_venues
      |> Enum.reject(fn %{venue: nearby} -> nearby.id == venue.id end)
      |> Enum.take(limit)
      |> Enum.map(fn %{venue: nearby, distance_km: distance} ->
        # Add hero_image_url to each venue
        updated_venue = Map.put(nearby, :hero_image_url, get_venue_image(nearby))
        %{venue: updated_venue, distance_km: distance}
      end)
    else
      []
    end
  end

  # Helper to convert Decimal to float
  def to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  def to_float(value), do: value

  # Count real available images (no fallbacks)
  def count_available_images(venue) do
    # Count Google images now stored in Waffle
    stored_images_count = if venue.google_place_images && is_list(venue.google_place_images),
      do: length(venue.google_place_images),
      else: 0

    # Count event hero image
    event_image_count = if venue.events && Enum.any?(venue.events) do
      event = List.first(venue.events)
      if event.hero_image && event.hero_image.file_name, do: 1, else: 0
    else
      0
    end

    # Return total
    stored_images_count + event_image_count
  end

  # Modified version to properly combine all image sources with consistent ordering
  def get_venue_image_at_position(venue, position) do
    alias TriviaAdvisor.Helpers.ImageUrlHelper

    # Check for events with hero_image
    {_event, event_image_url} =
      try do
        if venue.events && Enum.any?(venue.events) do
          event = List.first(venue.events)

          image_url = if event && event.hero_image && event.hero_image.file_name do
            try do
              # Use helper to generate URL
              ImageUrlHelper.get_image_url({event.hero_image.file_name, event}, TriviaAdvisor.Uploaders.HeroImage, :original)
            rescue
              e ->
                Logger.error("Error processing hero image URL: #{Exception.message(e)}")
                nil
            end
          else
            nil
          end

          {event, image_url}
        else
          {nil, nil}
        end
      rescue
        _ -> {nil, nil}
      end

    # Get stored place images if available
    stored_image_urls =
      try do
        if venue.google_place_images && is_list(venue.google_place_images) do
          venue.google_place_images
          |> Enum.filter(fn img -> is_map(img) && Map.has_key?(img, "local_path") && is_binary(img["local_path"]) end)
          |> Enum.sort_by(fn img -> Map.get(img, "position", 999) end)  # Sort by position
          |> Enum.map(fn image_data ->
            ImageUrlHelper.ensure_full_url(image_data["local_path"])
          end)
        else
          []
        end
      rescue
        _ -> []
      end

    # Combine all available images with hero image first
    all_images = []

    # Add hero image first if available
    all_images = if is_binary(event_image_url), do: [event_image_url | all_images], else: all_images

    # Add all stored images
    all_images = all_images ++ stored_image_urls

    # Now get the image at the requested position
    if position < length(all_images) && Enum.any?(all_images) do
      image = Enum.at(all_images, position)
      if is_binary(image), do: image, else: return_default_image(venue)
    else
      # If no image exists for this position, use our enhanced fallback image
      return_default_image(venue)
    end
  end

  def return_default_image(venue \\ nil) do
    # Use the venue_image helper instead of the removed fallback function
    TriviaAdvisorWeb.Helpers.ImageHelpers.get_venue_image(venue)
  end

  # Format distance for display
  def format_distance(distance_km) when is_float(distance_km) do
    cond do
      distance_km < 1 -> "#{round(distance_km * 1000)} m"
      true -> "#{:erlang.float_to_binary(distance_km, [decimals: 1])} km"
    end
  end
  def format_distance(_), do: "Unknown distance"

  # Helper to ensure URL is a full URL
  def ensure_full_url(path) do
    # Return a default image if path is nil or not a binary
    if is_nil(path) or not is_binary(path) do
      return_default_image()
    else
      try do
        cond do
          # Already a full URL
          String.starts_with?(path, "http") ->
            path

          # Check if using S3 storage in production
          Application.get_env(:waffle, :storage) == Waffle.Storage.S3 ->
            # Get S3 configuration
            s3_config = Application.get_env(:ex_aws, :s3, [])
            bucket = Application.get_env(:waffle, :bucket, "trivia-advisor")

            # For Tigris S3-compatible storage, we need to use a public URL pattern
            # that doesn't rely on object ACLs
            host = case s3_config[:host] do
              h when is_binary(h) -> h
              _ -> "fly.storage.tigris.dev"
            end

            # Format path correctly for S3 (remove leading slash)
            s3_path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path

            # Construct the full S3 URL
            # Using direct virtual host style URL
            "https://#{bucket}.#{host}/#{s3_path}"

          # Local development - use the app's URL config
          true ->
            if String.starts_with?(path, "/") do
              "#{TriviaAdvisorWeb.Endpoint.url()}#{path}"
            else
              "#{TriviaAdvisorWeb.Endpoint.url()}/#{path}"
            end
        end
      rescue
        e ->
          Logger.error("Error constructing URL from path #{inspect(path)}: #{Exception.message(e)}")
          return_default_image()
      end
    end
  end

  # Helper to get country information
  def get_country(venue) do
    country = cond do
      # Check if venue has a direct country_code
      Map.has_key?(venue, :country_code) ->
        %{code: venue.country_code, name: "Unknown", slug: "unknown"}
      # Try to safely extract country from city if it exists
      true ->
        try do
          if Map.has_key?(venue, :city) &&
             !is_nil(venue.city) &&
             !is_struct(venue.city, Ecto.Association.NotLoaded) &&
             Map.has_key?(venue.city, :country) &&
             !is_nil(venue.city.country) &&
             !is_struct(venue.city.country, Ecto.Association.NotLoaded) do
            venue.city.country
          else
            # Default fallback
            %{code: "US", name: "Unknown", slug: "unknown"}
          end
        rescue
          # If any error occurs, return a default
          _ -> %{code: "US", name: "Unknown", slug: "unknown"}
        end
    end

    # Debug log for venues related to France
    if venue.slug == "bar-le-national" do
      Logger.debug("Country for bar-le-national: #{inspect(country)}")
    end

    country
  end

  # Helper to get city information
  def get_city(venue) do
    if venue.city && !is_struct(venue.city, Ecto.Association.NotLoaded) do
      venue.city
    else
      # Fallback if city is not available or not loaded
      %{name: "Unknown", slug: "unknown"}
    end
  end

  # Helper to get country's currency
  def get_country_currency(venue) do
    country = get_country(venue)

    cond do
      # Check if currency code is stored in country data
      country && Map.has_key?(country, :currency_code) && country.currency_code ->
        country.currency_code
      # Use Countries library to get currency code if we have a country code
      country && country.code ->
        country_data = Countries.get(country.code)
        if country_data && Map.has_key?(country_data, :currency_code), do: country_data.currency_code, else: "USD"
      # Default to USD if we don't know
      true ->
        "USD"
    end
  end

  # Helper to format currency with proper symbol and localization
  def format_currency(amount_cents, currency_code) when is_number(amount_cents) do
    # Create Money struct with proper currency
    money = Money.new(amount_cents, currency_code)

    # Let the Money library handle the formatting
    Money.to_string(money)
  end
  def format_currency(_, _), do: "Free"

  # Helper to generate a Mapbox static map URL
  def get_static_map_url(venue, token) when is_binary(token) and byte_size(token) > 0 do
    # Convert Decimal to float if needed
    {lat, lng} = {to_float(venue.latitude), to_float(venue.longitude)}

    # Create a marker pin at the venue's coordinates
    marker = "pin-l-star+f74e4e(#{lng},#{lat})"
    # Size of the map image
    size = "600x400"
    # Zoom level (higher numbers = more zoomed in)
    zoom = 19
    # Use custom Mapbox style instead of default streets style
    style = "holden/cm7pbsjwv004401sc5z5ldatr"

    # Construct the URL
    "https://api.mapbox.com/styles/v1/#{style}/static/#{marker}/#{lng},#{lat},#{zoom}/#{size}?access_token=#{token}"
  end

  # Fallback if token is missing
  def get_static_map_url(venue, _token) do
    "https://placehold.co/600x400?text=Map+for+#{URI.encode(venue.name)}"
  end

  # Create a directions URL to Google Maps
  def get_directions_url(venue) do
    # Convert Decimal to float if needed
    lat = to_float(venue.latitude)
    lng = to_float(venue.longitude)

    # Use Google Maps directions URL with coordinates
    "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lng}&destination_place_id=#{venue.place_id}"
  end

  # Helper to format day name from day of week number
  def format_day(day) when is_integer(day) do
    # Using FormatHelpers.format_day_of_week that will be imported by the caller
    case day do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Unknown"
    end
  end

  def format_day(_), do: "TBA"

  # Helper to check if performer is loaded
  def performer_loaded?(event) do
    event &&
    event.performer &&
    !is_struct(event.performer, Ecto.Association.NotLoaded) &&
    event.performer.name
  end

  # Helper to get first event that has performer data
  def get_event_with_performer(venue) do
    if venue.events && Enum.any?(venue.events) do
      Enum.find(venue.events, fn event -> performer_loaded?(event) end)
    else
      nil
    end
  end

  # Helper to limit title length to 60 characters for SEO (Google typically shows ~60 chars)
  def limit_title_length(title) when is_binary(title) do
    max_length = 60

    if String.length(title) <= max_length do
      title
    else
      # Try to smartly truncate at a separator
      separators = [" · ", " by ", " in ", " ", "-"]

      # Try each separator, starting from the right side of the string
      Enum.reduce_while(separators, title, fn separator, acc ->
        # Find the rightmost position of the separator
        case String.split(acc, separator, parts: :infinity) do
          parts when length(parts) > 1 ->
            # Try removing parts from the end until we're under the max length
            Enum.reduce_while(1..length(parts), parts, fn i, parts_acc ->
              truncated = parts_acc |> Enum.drop(-i) |> Enum.join(separator)

              if String.length(truncated) <= max_length - 3 do
                # We found a good truncation point, add ellipsis and stop
                {:halt, {:halt, truncated <> "..."}}
              else
                # Keep trying with more parts removed
                {:cont, parts_acc}
              end
            end)
          _ ->
            # This separator isn't in the string or didn't help, try the next one
            {:cont, acc}
        end
      end)
      |> case do
        {:halt, result} -> result
        _ -> String.slice(title, 0, max_length - 3) <> "..."  # Hard truncate as fallback
      end
    end
  end

  # Helper to create a meta description for social sharing
  def get_meta_description(venue) do
    # Get next quiz date
    next_date = format_next_date(get_day_of_week(venue))
    day = format_day(get_day_of_week(venue))
    start_time = get_start_time(venue)

    # Check if there's a venue description available
    venue_desc = get_venue_description(venue)

    # Get organizer name if available
    organizer =
      try do
        if venue.events && Enum.any?(venue.events) do
          event = List.first(venue.events)
          if event && event.event_sources && is_list(event.event_sources) && Enum.any?(event.event_sources) do
            source = List.first(event.event_sources)
            if is_map(source) && Map.has_key?(source, :name) && is_binary(source.name), do: source.name, else: nil
          end
        else
          if is_map(venue.metadata), do: venue.metadata["source_name"], else: nil
        end
      rescue
        _ -> nil
      end

    # Create description based on available data
    cond do
      # If we have a venue description, date, time and organizer
      is_binary(venue_desc) && byte_size(venue_desc) > 10 && is_binary(organizer) ->
        # Truncate description if too long
        short_desc = if String.length(venue_desc) > 80, do: String.slice(venue_desc, 0, 80) <> "...", else: venue_desc
        "#{short_desc} Join us on #{next_date} (#{day}) at #{start_time}. Hosted by #{organizer}."

      # If we have a venue description but no organizer
      is_binary(venue_desc) && byte_size(venue_desc) > 10 ->
        short_desc = if String.length(venue_desc) > 100, do: String.slice(venue_desc, 0, 100) <> "...", else: venue_desc
        "#{short_desc} Join us on #{next_date} (#{day}) at #{start_time}."

      # If we have just the basic details
      true ->
        if is_binary(organizer) do
          "Join our pub quiz at #{venue.name} on #{day}s at #{start_time}. Hosted by #{organizer}. Meet other trivia enthusiasts and test your knowledge!"
        else
          "Join our pub quiz at #{venue.name} on #{day}s at #{start_time}. Meet other trivia enthusiasts and test your knowledge!"
        end
    end
  end

  # Helper to get the thumbnail URL for social sharing
  def get_social_sharing_image(venue) do
    alias TriviaAdvisor.Helpers.ImageUrlHelper

    # Get the venue image
    image_url = get_venue_image(venue)

    # Check if the image URL is valid
    if is_binary(image_url) and String.length(image_url) > 0 do
      # Convert from original to thumbnail URL
      # For paths containing /original_ in the URL, replace with /thumb_
      if String.contains?(image_url, "/original_") do
        String.replace(image_url, "/original_", "/thumb_")
      else
        # If it's not a standard path with original, just use the original image
        image_url
      end
    else
      # If no valid image URL is found, return a default image URL
      "#{TriviaAdvisorWeb.Endpoint.url()}/images/default-venue-thumb.jpg"
    end
  end
end

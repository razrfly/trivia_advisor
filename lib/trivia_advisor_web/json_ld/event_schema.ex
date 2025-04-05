defmodule TriviaAdvisorWeb.JsonLd.EventSchema do
  @moduledoc """
  Generates JSON-LD structured data for events according to schema.org and Google guidelines.

  This module converts venue and event data into properly formatted structured data
  for better SEO and Google rich results.
  """

  require Logger

  @doc """
  Generates JSON-LD structured data for a venue and its events.

  ## Parameters
    - venue: A venue struct with preloaded events and event_sources

  ## Returns
    - A JSON-LD string ready to be included in the page head
  """
  def generate_venue_event_json_ld(venue) do
    # Get the first event or nil if no events
    event = if venue.events && Enum.any?(venue.events) do
      List.first(venue.events)
    else
      nil
    end

    # Generate the JSON-LD data
    json_ld_data = generate_event_schema(venue, event)

    # Return the JSON-LD as a string with proper formatting
    Jason.encode!(json_ld_data)
  end

  @doc """
  Generates schema.org Event structured data for a venue and event.

  ## Parameters
    - venue: A venue struct with address, coordinates, etc.
    - event: An event struct or nil if no event is available

  ## Returns
    - A map representing the JSON-LD structured data
  """
  def generate_event_schema(venue, event) do
    # Basic venue information
    venue_data = %{
      "@context" => "https://schema.org",
      "@type" => "Event",
      "name" => venue.name,
      "location" => generate_location_schema(venue),
      "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
      "eventStatus" => "https://schema.org/EventScheduled"
    }

    # Always add description from venue if available - safely handle nil metadata
    venue_metadata = venue.metadata || %{}
    venue_description = Map.get(venue_metadata, "description") || Map.get(venue_metadata, :description)
    venue_data = maybe_add_description(venue_data, venue_description)

    # Calculate dates if event exists
    venue_data = if event do
      day_of_week = event.day_of_week
      start_time = event.start_time

      # Calculate the next occurrence date
      next_date = calculate_next_occurrence(day_of_week)

      # Format start and end times
      {start_datetime, end_datetime} = format_event_times(next_date, start_time)

      # Add event-specific information
      venue_data
      |> Map.put("startDate", start_datetime)
      |> Map.put("endDate", end_datetime)
      |> maybe_add_description(event.description)
      |> maybe_add_price(event.entry_fee_cents, venue)
      |> maybe_add_performer(event.performer)
      |> add_organizer(event, venue)
    else
      # Default values if no event
      next_monday = calculate_next_occurrence(1) # Monday
      {start_datetime, end_datetime} = format_event_times(next_monday, ~T[19:00:00])

      venue_data
      |> Map.put("startDate", start_datetime)
      |> Map.put("endDate", end_datetime)
    end

    # Add images if available
    venue_data
    |> add_images(venue, event)
  end

  @doc """
  Generates schema.org Place structured data for a venue.

  ## Parameters
    - venue: A venue struct with address information

  ## Returns
    - A map representing the Place information
  """
  def generate_location_schema(venue) do
    # Extract address components
    address_components = extract_address_components(venue.address)

    # Create the Place schema
    %{
      "@type" => "Place",
      "name" => venue.name,
      "address" => %{
        "@type" => "PostalAddress",
        "streetAddress" => address_components.street_address,
        "addressLocality" => address_components.locality,
        "postalCode" => venue.postcode || address_components.postal_code,
        "addressRegion" => address_components.region,
        "addressCountry" => venue.city && venue.city.country && venue.city.country.code || "US"
      }
    }
  end

  # Add images to the event schema - UPDATED to use exact same URLs as gallery
  defp add_images(schema, venue, event) do
    # List to collect exact image URLs in the order they should appear
    image_urls = []

    # Try to get the hero image first (exactly as shown in gallery)
    hero_image_url = if event && event.hero_image && event.hero_image.file_name do
      try do
        # Use the exact bucket/path format seen in the gallery examples
        bucket = Application.get_env(:waffle, :bucket, "trivia-app")
        path = "uploads/venues/#{venue.slug}/original_#{Path.basename(event.hero_image.file_name)}"
        url = "https://#{bucket}.fly.storage.tigris.dev/#{path}"
        url
      rescue
        e ->
          Logger.error("Error getting hero image URL: #{Exception.message(e)}")
          nil
      end
    end

    # Add hero image to list if it exists
    image_urls = if hero_image_url, do: [hero_image_url | image_urls], else: image_urls

    # Try to get Google place images using the exact same URL format
    google_image_urls = if venue.google_place_images && is_list(venue.google_place_images) do
      bucket = Application.get_env(:waffle, :bucket, "trivia-app")

      venue.google_place_images
      |> Enum.with_index()
      |> Enum.map(fn {_image, idx} ->
        # Use the format seen in the example gallery
        "https://#{bucket}.fly.storage.tigris.dev/uploads/google_place_images/#{venue.slug}/original_google_place_#{idx + 1}.jpg"
      end)
      |> Enum.take(4) # Take only the first 4 as shown in gallery
    else
      []
    end

    # Combine all images
    image_urls = image_urls ++ google_image_urls

    # Add images to schema
    if Enum.any?(image_urls) do
      Map.put(schema, "image", image_urls)
    else
      # Add a default image
      Map.put(schema, "image", ["https://placehold.co/600x400?text=#{URI.encode(venue.name)}"])
    end
  end

  # Calculate the next occurrence of a day of week
  defp calculate_next_occurrence(day_of_week) when is_integer(day_of_week) do
    today = Date.utc_today()
    today_dow = Date.day_of_week(today)

    days_until = if day_of_week >= today_dow do
      day_of_week - today_dow
    else
      7 - today_dow + day_of_week
    end

    Date.add(today, days_until)
  end

  # Format event times as ISO8601 strings with the proper timezone
  defp format_event_times(date, start_time) do
    # Get timezone from config, default to UTC
    timezone = Application.get_env(:trivia_advisor, :default_timezone, "Etc/UTC")

    # Calculate the DateTime for start
    {:ok, start_datetime} = DateTime.new(date, start_time, timezone)

    # Calculate end time (assume 3 hours later)
    end_datetime = DateTime.add(start_datetime, 3 * 60 * 60, :second)

    # Format as ISO8601 strings
    {DateTime.to_iso8601(start_datetime), DateTime.to_iso8601(end_datetime)}
  end

  # Add description if available
  defp maybe_add_description(schema, nil), do: schema
  defp maybe_add_description(schema, ""), do: schema
  defp maybe_add_description(schema, description) when is_binary(description) do
    # Only add description if it's not already present
    if Map.has_key?(schema, "description") do
      schema
    else
      Map.put(schema, "description", description)
    end
  end

  # Add price information if available
  defp maybe_add_price(schema, nil, _venue), do: schema
  defp maybe_add_price(schema, 0, _venue), do: schema
  defp maybe_add_price(schema, entry_fee_cents, venue) when is_integer(entry_fee_cents) and entry_fee_cents > 0 do
    # Get currency code from venue's country
    currency_code = get_currency_code(venue)
    price = entry_fee_cents / 100.0

    offer = %{
      "@type" => "Offer",
      "price" => price,
      "priceCurrency" => currency_code,
      "availability" => "https://schema.org/InStock",
      "validFrom" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add URL if venue has a website
    offer = if venue.website do
      Map.put(offer, "url", venue.website)
    else
      offer
    end

    Map.put(schema, "offers", offer)
  end

  # Get currency code from venue's country
  defp get_currency_code(venue) do
    try do
      if venue.city && venue.city.country && venue.city.country.code do
        country_data = Countries.get(venue.city.country.code)
        if country_data, do: country_data.currency_code, else: "USD"
      else
        "USD"
      end
    rescue
      _ -> "USD"
    end
  end

  # Add performer information if available
  defp maybe_add_performer(schema, nil), do: schema
  defp maybe_add_performer(schema, performer) do
    if performer.name do
      performer_data = %{
        "@type" => "Person",
        "name" => performer.name
      }

      Map.put(schema, "performer", performer_data)
    else
      schema
    end
  end

  # Always try to add organizer information from any available source
  defp add_organizer(schema, event, venue) do
    # First try to find an event source from the event
    schema = try do
      if event && event.event_sources && is_list(event.event_sources) do
        source = find_valid_event_source(event.event_sources)
        if source do
          organizer = %{
            "@type" => "Organization",
            "name" => source.name,
            "url" => source.url
          }
          Map.put(schema, "organizer", organizer)
        else
          schema
        end
      else
        schema
      end
    rescue
      e ->
        Logger.error("Error finding event source: #{Exception.message(e)}")
        schema
    end

    # If no organizer added yet, try from venue metadata
    if !Map.has_key?(schema, "organizer") do
      try do
        # Check venue metadata safely
        venue_metadata = venue.metadata || %{}
        source_name = Map.get(venue_metadata, "source_name") || Map.get(venue_metadata, :source_name)
        source_url = Map.get(venue_metadata, "source_url") || Map.get(venue_metadata, :source_url)

        if source_name && source_url do
          organizer = %{
            "@type" => "Organization",
            "name" => source_name,
            "url" => source_url
          }
          Map.put(schema, "organizer", organizer)
        else
          # Fallback to a default source like "Question One" from the example
          Map.put(schema, "organizer", %{
            "@type" => "Organization",
            "name" => "Question One",
            "url" => "https://questionone.com"
          })
        end
      rescue
        e ->
          Logger.error("Error adding organizer from venue metadata: #{Exception.message(e)}")
          # Default fallback organizer
          Map.put(schema, "organizer", %{
            "@type" => "Organization",
            "name" => "Question One",
            "url" => "https://questionone.com"
          })
      end
    else
      schema
    end
  end

  # Helper to find a valid event source
  defp find_valid_event_source(event_sources) do
    # Try to find a source with both name and URL
    source = Enum.find_value(event_sources, nil, fn es ->
      if es && es.source && is_map(es.source) &&
         (Map.has_key?(es.source, :name) || Map.has_key?(es.source, "name")) &&
         (Map.has_key?(es.source, :url) || Map.has_key?(es.source, "url")) do

        name = es.source[:name] || es.source["name"]
        url = es.source[:url] || es.source["url"]

        if is_binary(name) && is_binary(url) do
          %{name: name, url: url}
        else
          nil
        end
      else
        nil
      end
    end)

    # If nothing found, check for source with just a name, and use default URL
    if !source do
      Enum.find_value(event_sources, nil, fn es ->
        if es && es.source && is_map(es.source) &&
           (Map.has_key?(es.source, :name) || Map.has_key?(es.source, "name")) do

          name = es.source[:name] || es.source["name"]

          if is_binary(name) do
            %{name: name, url: "https://questionone.com"}
          else
            nil
          end
        else
          nil
        end
      end)
    else
      source
    end
  end

  # Extract address components from a string address
  defp extract_address_components(address) when is_binary(address) do
    # Default values
    defaults = %{
      street_address: address,
      locality: "",
      postal_code: "",
      region: ""
    }

    # Try to extract more detailed components
    # This is a simplified version - in a real implementation,
    # you might want to use more sophisticated parsing or geocoding
    try do
      # Split by commas
      parts = String.split(address, ",") |> Enum.map(&String.trim/1)

      case length(parts) do
        1 ->
          # Just a street address
          %{defaults | street_address: Enum.at(parts, 0) || ""}

        2 ->
          # Likely street address and city
          %{defaults |
            street_address: Enum.at(parts, 0) || "",
            locality: Enum.at(parts, 1) || ""
          }

        3 ->
          # Likely street address, city, region/postal code
          last_part = Enum.at(parts, 2) || ""
          {region, postal_code} = extract_region_postal(last_part)

          %{defaults |
            street_address: Enum.at(parts, 0) || "",
            locality: Enum.at(parts, 1) || "",
            region: region,
            postal_code: postal_code
          }

        _ ->
          # More parts - try to be smart about it
          street_address = Enum.at(parts, 0) || ""
          locality = Enum.at(parts, 1) || ""
          last_part = List.last(parts) || ""
          {region, postal_code} = extract_region_postal(last_part)

          %{defaults |
            street_address: street_address,
            locality: locality,
            region: region,
            postal_code: postal_code
          }
      end
    rescue
      _ -> defaults
    end
  end

  # Handle nil address
  defp extract_address_components(nil), do: %{
    street_address: "",
    locality: "",
    postal_code: "",
    region: ""
  }

  # Extract region and postal code from a string
  defp extract_region_postal(str) do
    # Try to identify postal codes with regex
    case Regex.run(~r/([A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}|[0-9]{5}(-[0-9]{4})?)/i, str) do
      [postal_code | _] ->
        # Found a postal code - the rest is likely the region
        region = String.replace(str, postal_code, "") |> String.trim()
        {region, postal_code}

      nil ->
        # No postal code identified - try to split by space
        parts = String.split(str, " ", trim: true)
        if length(parts) > 1 do
          possible_postal = List.last(parts)

          if Regex.match?(~r/^[0-9A-Z\-]+$/i, possible_postal) do
            region = Enum.join(Enum.slice(parts, 0..-2//1), " ")
            {region, possible_postal}
          else
            {str, ""}
          end
        else
          {str, ""}
        end
    end
  end
end

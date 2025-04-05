defmodule TriviaAdvisorWeb.JsonLd.EventSchema do
  @moduledoc """
  Generates JSON-LD structured data for events according to schema.org and Google guidelines.

  This module converts venue and event data into properly formatted structured data
  for better SEO and Google rich results.
  """

  require Logger
  alias TriviaAdvisor.Events.Event

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
      |> maybe_add_organizer(event)
    else
      # Default values if no event
      next_monday = calculate_next_occurrence(1) # Monday
      {start_datetime, end_datetime} = format_event_times(next_monday, ~T[19:00:00])

      venue_data
      |> Map.put("startDate", start_datetime)
      |> Map.put("endDate", end_datetime)
      |> maybe_add_description(venue.metadata["description"])
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

  # Add images to the event schema
  defp add_images(schema, venue, event) do
    # Try to get the hero image if available
    hero_image = if event && event.hero_image && event.hero_image.file_name do
      # Generate full URL for hero image
      image_url = get_image_url(event.hero_image, event)
      if image_url, do: [image_url], else: []
    else
      []
    end

    # Try to get Google place images
    google_images = if venue.google_place_images && is_list(venue.google_place_images) do
      venue.google_place_images
      |> Enum.filter(fn img -> is_map(img) end)
      |> Enum.map(fn image ->
        cond do
          Map.has_key?(image, "original_url") && is_binary(image["original_url"]) ->
            image["original_url"]
          Map.has_key?(image, "local_path") && is_binary(image["local_path"]) ->
            get_image_url(image["local_path"], venue)
          true ->
            nil
        end
      end)
      |> Enum.filter(&is_binary/1)
    else
      []
    end

    # Combine images and add to schema
    images = hero_image ++ google_images

    if Enum.any?(images) do
      Map.put(schema, "image", images)
    else
      # Add a default image
      Map.put(schema, "image", ["https://placehold.co/600x400?text=#{URI.encode(venue.name)}"])
    end
  end

  # Get a full URL for an image
  defp get_image_url(image, context) do
    try do
      cond do
        is_binary(image) && String.starts_with?(image, "http") ->
          image

        is_map(image) && Map.has_key?(image, :file_name) ->
          # For waffle images
          base_url = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)[:url]
          host = base_url[:host]
          scheme = base_url[:scheme] || "https"

          if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
            bucket = Application.get_env(:waffle, :bucket, "trivia-advisor")
            s3_config = Application.get_env(:ex_aws, :s3, [])
            host = s3_config[:host] || "fly.storage.tigris.dev"

            module = case context do
              %Event{} -> TriviaAdvisor.Uploaders.HeroImage
              _ -> TriviaAdvisor.Uploaders.ProfileImage
            end

            url = module.url({image, context}, :original)
            s3_path = if String.starts_with?(url, "/"), do: String.slice(url, 1..-1//1), else: url

            "https://#{bucket}.#{host}/#{s3_path}"
          else
            # Development
            "#{scheme}://#{host}/uploads/venues/#{context.venue && context.venue.slug}/original_#{Path.basename(image.file_name)}"
          end

        true ->
          nil
      end
    rescue
      e ->
        Logger.error("Error getting image URL: #{Exception.message(e)}")
        nil
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
    Map.put(schema, "description", description)
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

  # Add organizer information if available from event sources
  defp maybe_add_organizer(schema, event) do
    try do
      # Find an event source with a name and URL
      event_source = Enum.find(event.event_sources, fn es ->
        es.source && es.source.name && es.source.url
      end)

      if event_source do
        organizer = %{
          "@type" => "Organization",
          "name" => event_source.source.name,
          "url" => event_source.source.url
        }

        Map.put(schema, "organizer", organizer)
      else
        schema
      end
    rescue
      _ -> schema
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

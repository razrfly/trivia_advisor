defmodule TriviaAdvisor.Scraping.Scrapers.Quizmeisters.VenueExtractor do
  @moduledoc """
  Extracts venue data specifically from Quizmeisters HTML structure.
  """

  require Logger

  def extract_venue_data(document, url, _raw_title) do
    try do
      # Extract description from the venue-specific description first
      description = document
        |> Floki.find(".venue-description.w-richtext:not(.trivia-generic):not(.bingo-generic):not(.survey-generic) p")
        |> Enum.map(&Floki.text/1)
        |> Enum.join("\n\n")
        |> String.trim()
        |> filter_lorem_ipsum()

      # If no venue-specific description, get the trivia generic one
      description = if description == "",
        do: document
          |> Floki.find(".venue-description.trivia-generic.w-richtext p")
          |> Enum.map(&Floki.text/1)
          |> Enum.join("\n\n")
          |> String.trim()
          |> filter_lorem_ipsum(),
        else: description

      # Extract hero image
      hero_image_url = document
        |> Floki.find(".venue-photo")
        |> Floki.attribute("src")
        |> List.first()

      # Extract performer info
      performer = document
        |> Floki.find(".host-info")
        |> extract_performer_info()

      # Enhanced logging for debugging performer extraction
      Logger.debug("🎭 Extracted performer: #{inspect(performer)}")

      # Extract social links from the icon block
      social_links = document
        |> Floki.find(".icon-block a")
        |> Enum.reduce(%{website: nil, facebook: nil, instagram: nil}, fn el, acc ->
          href = Floki.attribute(el, "href") |> List.first()
          cond do
            Floki.find(el, "img[alt*='website']") |> Enum.any?() ->
              %{acc | website: href}
            Floki.find(el, "img[alt*='facebook']") |> Enum.any?() ->
              %{acc | facebook: href}
            Floki.find(el, "img[alt*='instagram']") |> Enum.any?() ->
              %{acc | instagram: href}
            true -> acc
          end
        end)

      # Extract phone from the venue block
      phone = document
        |> Floki.find(".venue-block .paragraph")
        |> Enum.map(&Floki.text/1)
        |> Enum.find(fn text ->
          String.match?(text, ~r/^\+?[\d\s-]{8,}$/)
        end)
        |> case do
          nil -> nil
          number -> String.trim(number)
        end

      # Check if venue is on break
      on_break = document
        |> Floki.find(".on-break")
        |> Enum.any?()

      {:ok, Map.merge(%{
        description: description,
        hero_image_url: hero_image_url,
        on_break: on_break,
        phone: phone,
        performer: performer
      }, social_links)}
    rescue
      e ->
        Logger.error("Failed to extract venue data from #{url}: #{Exception.message(e)}")
        {:error, "Failed to extract venue data: #{Exception.message(e)}"}
    end
  end

  defp extract_performer_info(host_info) do
    case host_info do
      [] ->
        Logger.debug("❌ No host_info elements found for performer extraction")
        nil
      elements ->
        Logger.debug("🔍 Found host_info elements: #{Enum.count(elements)}")

        # Dump the entire elements structure to debug HTML structure
        Logger.debug("🔍 Host info HTML structure: #{inspect(elements)}")

        # Extract name with more robust error handling and debugging
        name_elements = Floki.find(elements, ".host-name")
        Logger.debug("🔍 Found #{Enum.count(name_elements)} name elements")

        name = if Enum.empty?(name_elements) do
          Logger.debug("❌ No host-name elements found")
          ""
        else
          raw_name = Floki.text(name_elements) |> String.trim()
          Logger.debug("🔍 Extracted raw performer name: '#{raw_name}'")
          raw_name
        end

        # Find all host images with more detailed logging
        all_images = Floki.find(elements, ".host-image")
        Logger.debug("🔍 Found #{Enum.count(all_images)} total host image elements")

        # Dump all image elements for debugging
        Enum.each(all_images, fn img ->
          class = Floki.attribute(img, "class") |> List.first() || ""
          src = Floki.attribute(img, "src") |> List.first() || ""
          Logger.debug("🔍 Image element: class='#{class}', src='#{src}'")
        end)

        # Filter out placeholder images
        images = all_images
          |> Enum.filter(fn img ->
            class = Floki.attribute(img, "class") |> List.first() || ""
            src = Floki.attribute(img, "src") |> List.first() || ""
            valid = not String.contains?(class, "placeholder") and
                   not String.contains?(class, "w-condition-invisible") and
                   src != ""

            if not valid do
              Logger.debug("🔍 Filtering out image with class='#{class}', src='#{src}'")
            end

            valid
          end)

        Logger.debug("🔍 Found #{Enum.count(images)} valid host images after filtering")

        # Get the src attribute of the first real image
        profile_image = case images do
          [] ->
            Logger.debug("❌ No valid host images found")
            nil
          [img | _] ->
            image_src = Floki.attribute(img, "src") |> List.first()
            Logger.debug("✅ Found host image: #{image_src}")
            image_src
        end

        # Critical change: Return performer data if we have EITHER a name OR an image
        # This ensures we don't miss performers with only an image but no name
        cond do
          name != "" and profile_image ->
            Logger.info("✅ Found complete performer data: name='#{name}', has_image=true, image_url='#{String.slice(profile_image, 0, 50)}...'")
            %{name: name, profile_image: profile_image}

          name != "" ->
            Logger.info("✅ Found performer with name only: '#{name}'")
            %{name: name, profile_image: nil}

          profile_image ->
            # Generate a venue-specific name based on image filename
            # Extract information from image path if possible
            image_basename = Path.basename(profile_image)
            # Try to extract performer name from image filename
            extracted_name = image_basename
              |> String.split(["-", "_"], trim: true)
              |> Enum.filter(fn part ->
                 String.length(part) > 2 and
                 not String.match?(part, ~r/^\d+/) and
                 not String.match?(part, ~r/^[0-9a-f]{32}$/i)
              end)
              |> Enum.join(" ")
              |> String.trim()
              |> case do
                   "" -> "Quizmeisters Host"
                   name -> String.capitalize(name)
                 end

            Logger.info("✅ Found performer with image only - extracted name: '#{extracted_name}' from image: #{image_basename}")
            %{name: extracted_name, profile_image: profile_image}

          true ->
            Logger.debug("❌ No useful performer data found")
            nil
        end
    end
  end

  defp filter_lorem_ipsum(text) when is_binary(text) do
    if String.starts_with?(text, "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore e"), do: "", else: text
  end
  defp filter_lorem_ipsum(_), do: ""
end

defmodule TriviaAdvisor.Scraping.VenueExtractor do
  @moduledoc "Handles venue data extraction from HTML documents."

  require Logger

  def extract_venue_data(document, url, raw_title) do
    title = raw_title
    |> String.replace(~r/^PUB QUIZ[[:punct:]]*/i, "")
    |> String.replace(~r/^[–\s]+/, "")
    |> String.replace(~r/\s+[–].*$/i, "")
    |> String.trim()

    address = find_text_with_icon(document, "pin")
    time_text = find_text_with_icon(document, "calendar")
    fee_text = find_text_with_icon(document, "tag")
    phone = find_text_with_icon(document, "phone")

    website = document
    |> Floki.find("a[href]:fl-contains('Visit Website')")
    |> Floki.attribute("href")
    |> List.first()

    description = document
    |> Floki.find(".post-content-area p")
    |> Enum.map(&Floki.text/1)
    |> Enum.join("\n\n")
    |> String.trim()

    hero_image_url = document
    |> Floki.find("img[src*='wp-content/uploads']")
    |> Floki.attribute("src")
    |> List.first()

    # Check required fields
    if is_nil(address) or is_nil(time_text) or is_nil(title) do
      Logger.error("""
      Skipping venue at #{url} due to missing required fields:
        Address: #{inspect(address)}
        Time: #{inspect(time_text)}
        Title: #{inspect(title)}
      """)
      nil
    else
      venue_data = %{
        raw_title: raw_title,
        title: title,
        address: address,
        time_text: time_text,
        fee_text: fee_text,
        phone: phone,
        website: website,
        description: description,
        hero_image_url: hero_image_url,
        url: url
      }

      log_venue_details(venue_data)
      venue_data
    end
  end

  defp find_text_with_icon(document, icon_name) do
    case document
         |> Floki.find(".text-with-icon")
         |> Enum.find(fn el ->
           Floki.find(el, "use")
           |> Enum.any?(fn use ->
             href = Floki.attribute(use, "href") |> List.first()
             xlink = Floki.attribute(use, "xlink:href") |> List.first()
             (href && String.ends_with?(href, "##{icon_name}")) ||
             (xlink && String.ends_with?(xlink, "##{icon_name}"))
           end)
         end) do
      nil ->
        Logger.warning("Missing icon text for #{icon_name}")
        nil

      el ->
        el |> Floki.find(".text-with-icon__text") |> Floki.text() |> String.trim()
    end
  end

  defp log_venue_details(venue) do
    Logger.info("""
    Extracted Venue Data:
      Raw Title: #{inspect(venue.raw_title)}
      Cleaned Title: #{inspect(venue.title)}
      Address: #{inspect(venue.address)}
      Time: #{inspect(venue.time_text)}
      Fee: #{inspect(venue.fee_text)}
      Phone: #{inspect(venue.phone)}
      Website: #{inspect(venue.website)}
      Description: #{inspect(String.slice(venue.description || "", 0..100))}
      Hero Image: #{inspect(venue.hero_image_url)}
    """)
  end
end

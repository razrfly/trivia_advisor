defmodule TriviaAdvisor.Scraping.Scrapers.QuestionOne.VenueExtractor do
  @moduledoc """
  Extracts venue data specifically from Question One HTML structure.
  """

  require Logger
  alias TriviaAdvisor.Scraping.Helpers.VenueHelpers

  def extract_venue_data(document, url, raw_title) do
    title = raw_title
    |> String.replace(~r/^PUB QUIZ[[:punct:]]*/i, "")
    |> String.replace(~r/^[–\s]+/, "")
    |> String.replace(~r/\s+[–].*$/i, "")
    |> String.trim()

    with {:ok, address} <- find_text_with_icon(document, "pin"),
         {:ok, time_text} <- find_text_with_icon(document, "calendar") do

      fee_text = case find_text_with_icon(document, "tag") do
        {:ok, value} -> value
        {:error, _} -> nil
      end

      phone = case find_text_with_icon(document, "phone") do
        {:ok, value} -> value
        {:error, _} -> nil
      end

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

      hero_image = case VenueHelpers.download_image(hero_image_url) do
        {:ok, image_data} -> image_data
        _ -> nil
      end

      venue_data = %{
        raw_title: raw_title,
        title: title,
        address: address,
        time_text: time_text,
        day_of_week: VenueHelpers.parse_day_of_week(time_text),
        start_time: VenueHelpers.parse_time(time_text),
        frequency: :weekly,
        fee_text: fee_text,
        phone: phone,
        website: website,
        description: description,
        hero_image: hero_image,
        hero_image_url: hero_image_url,
        url: url
      }

      VenueHelpers.log_venue_details(venue_data)
      {:ok, venue_data}
    else
      {:error, reason} ->
        error_msg = "Failed to extract required fields: #{reason}"
        Logger.error("#{error_msg} for venue at #{url}")
        {:error, error_msg}
    end
  end

  # Finds text associated with a specific icon in Question One's HTML structure.
  # Returns {:ok, text} or {:error, reason}
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
        reason = "Missing icon text for #{icon_name}"
        Logger.warning(reason)
        {:error, reason}

      el ->
        text = el |> Floki.find(".text-with-icon__text") |> Floki.text() |> String.trim()
        if String.trim(text) == "", do: {:error, "Empty text for #{icon_name}"}, else: {:ok, text}
    end
  end
end

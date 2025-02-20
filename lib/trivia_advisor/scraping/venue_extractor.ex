defmodule TriviaAdvisor.Scraping.VenueExtractor do
  @moduledoc "Handles venue data extraction from HTML documents."

  require Logger

  def extract_venue_data(document, url, raw_title) do
    title = raw_title
    |> String.replace(~r/^PUB QUIZ[[:punct:]]*/i, "")
    |> String.replace(~r/^[–\s]+/, "")
    |> String.replace(~r/\s+[–].*$/i, "")
    |> String.trim()

    with {:ok, address} <- find_text_with_icon(document, "pin"),
         {:ok, time_text} <- find_text_with_icon(document, "calendar") do

      # Optional fields can use case
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

      hero_image = case download_hero_image(hero_image_url) do
        {:ok, image_data} -> image_data
        _ -> nil
      end

      venue_data = %{
        raw_title: raw_title,
        title: title,
        address: address,
        time_text: time_text,
        day_of_week: parse_day_of_week(time_text),
        start_time: parse_time(time_text),
        frequency: :weekly,  # Default for now
        fee_text: fee_text,
        phone: phone,
        website: website,
        description: description,
        hero_image: hero_image,
        hero_image_url: hero_image_url,
        url: url
      }

      log_venue_details(venue_data)
      {:ok, venue_data}
    else
      {:error, reason} ->
        error_msg = "Failed to extract required fields: #{reason}"
        Logger.error("#{error_msg} for venue at #{url}")
        {:error, error_msg}
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
        reason = "Missing icon text for #{icon_name}"
        Logger.warning(reason)
        {:error, reason}

      el ->
        text = el |> Floki.find(".text-with-icon__text") |> Floki.text() |> String.trim()
        if String.trim(text) == "", do: {:error, "Empty text for #{icon_name}"}, else: {:ok, text}
    end
  end

  defp parse_day_of_week(time_text) do
    cond do
      String.contains?(time_text, "Monday") -> 1
      String.contains?(time_text, "Tuesday") -> 2
      String.contains?(time_text, "Wednesday") -> 3
      String.contains?(time_text, "Thursday") -> 4
      String.contains?(time_text, "Friday") -> 5
      String.contains?(time_text, "Saturday") -> 6
      String.contains?(time_text, "Sunday") -> 7
      true -> raise "Invalid day in time_text: #{time_text}"
    end
  end

  defp parse_time(time_text) do
    case Regex.run(~r/(\d{1,2}[:.]?\d{2})/, time_text) do
      [_, time] ->
        time
        |> String.replace(".", ":")  # normalize separator
        |> String.pad_leading(5, "0")  # pad single digit hours
        |> then(fn t -> t <> ":00" end)
        |> Time.from_iso8601!()
      nil -> raise "Could not parse time from: #{time_text}"
    end
  end

  defp log_venue_details(venue) do
    Logger.info("""
    📍 Extracted Venue Details:
      Title (Raw)   : #{inspect(venue.raw_title)}
      Title (Clean) : #{inspect(venue.title)}
      Address       : #{inspect(venue.address)}
      Time Text     : #{inspect(venue.time_text)}
      Day of Week   : #{inspect(venue.day_of_week)}
      Start Time    : #{inspect(venue.start_time)}
      Frequency     : #{inspect(venue.frequency)}
      Fee          : #{inspect(venue.fee_text)}
      Phone        : #{inspect(venue.phone || "Not provided")}
      Website      : #{inspect(venue.website || "Not provided")}
      Description  : #{inspect(String.slice(venue.description || "", 0..100))}...
      Hero Image   : #{inspect(venue.hero_image_url || "Not provided")}
      Source URL   : #{inspect(venue.url)}
    """)
  end

  defp download_hero_image(nil), do: {:error, :no_image}
  defp download_hero_image(url) do
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        tmp_path = Path.join(System.tmp_dir!(), "#{:crypto.strong_rand_bytes(16) |> Base.encode16()}")
        File.write!(tmp_path, body)
        {:ok, %{
          path: tmp_path,
          file_name: Path.basename(url)
        }}
      _ ->
        {:error, :download_failed}
    end
  end
end

defmodule TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.VenueExtractor do
  require Logger

  @doc """
  Extracts venue data from a venue block HTML string.
  Returns {:ok, venue_data} or {:error, reason}.
  """
  def extract_venue_data(block) do
    with {:ok, document} <- Floki.parse_fragment(block) do
      fields = [
        {:venue_id, extract_venue_id(document)},
        {:url, extract_url(document)},
        {:title, extract_title(document)},
        {:address, extract_address(document)},
        {:lat, extract_lat(document)},
        {:lon, extract_lon(document)},
        {:brand, extract_brand(document)},
        {:time_text, extract_time_text(document)},
        {:logo_url, extract_logo_url(document)}
      ]

      missing_fields = Enum.filter(fields, fn {_name, value} -> is_nil(value) end)

      if Enum.empty?(missing_fields) do
        fields_map = Map.new(fields)

        {:ok, %{
          venue_id: fields_map.venue_id,
          url: fields_map.url,
          title: fields_map.title,
          address: fields_map.address,
          latitude: fields_map.lat,
          longitude: fields_map.lon,
          brand: fields_map.brand,
          time_text: fields_map.time_text,
          logo_url: fields_map.logo_url,
          source_url: fields_map.url
        }}
      else
        missing = missing_fields |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")
        Logger.warning("Missing required fields: #{missing}")
        Logger.debug("HTML block: #{inspect(block)}")
        {:error, :missing_required_field}
      end
    else
      error ->
        Logger.warning("Error parsing HTML: #{inspect(error)}")
        {:error, error}
    end
  end

  defp extract_venue_id(document) do
    document
    |> Floki.attribute("id")
    |> List.first()
    |> case do
      nil -> nil
      id -> String.replace(id, "quizBlock-", "")
    end
  end

  defp extract_url(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_title(document) do
    document
    |> Floki.find("h2")
    |> Floki.text()
    |> case do
      "" -> nil
      text -> String.trim(text)
    end
  end

  defp extract_address(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("data-address")
    |> List.first()
  end

  defp extract_lat(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("data-lat")
    |> List.first()
    |> parse_float()
  end

  defp extract_lon(document) do
    document
    |> Floki.find("a")
    |> Floki.attribute("data-lon")
    |> List.first()
    |> parse_float()
  end

  defp extract_brand(document) do
    document
    |> Floki.find(".quizBlock__brand")
    |> Floki.text()
    |> case do
      "" -> nil
      text -> String.trim(text)
    end
  end

  defp extract_time_text(document) do
    document
    |> Floki.find("time")
    |> Floki.text()
    |> case do
      "" -> nil
      text -> String.trim(text)
    end
  end

  defp extract_logo_url(document) do
    document
    |> Floki.find(".quizBlock__logo")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp parse_float(nil), do: nil
  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> nil
    end
  end
end

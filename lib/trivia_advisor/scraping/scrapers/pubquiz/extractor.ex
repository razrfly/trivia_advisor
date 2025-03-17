defmodule TriviaAdvisor.Scraping.Scrapers.Pubquiz.Extractor do
  @moduledoc """
  HTML extraction logic for pubquiz.pl
  """

  def extract_cities(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".shop-page-categories .category-pill")
    |> Enum.map(fn {"a", attrs, _} ->
      Enum.find_value(attrs, fn
        {"href", url} -> url
        _ -> nil
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&String.contains?(&1, "liga")) # Filter out the "Liga" link
  end

  def extract_venues(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".e-n-tabs-content .product-category")
    |> Enum.map(fn venue ->
      %{
        name: extract_venue_name(venue),
        url: extract_venue_url(venue),
        image_url: extract_venue_image(venue)
      }
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp extract_venue_name(venue) do
    venue
    |> Floki.find(".woocommerce-loop-category__title")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_venue_url(venue) do
    venue
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_venue_image(venue) do
    venue
    |> Floki.find("img")
    |> Floki.attribute("src")
    |> List.first()
  end
end

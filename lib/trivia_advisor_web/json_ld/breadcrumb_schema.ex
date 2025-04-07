defmodule TriviaAdvisorWeb.JsonLd.BreadcrumbSchema do
  @moduledoc """
  Generates JSON-LD structured data for breadcrumbs according to schema.org guidelines.

  This module provides functions to create properly formatted JSON-LD breadcrumb lists
  for better SEO and Google rich results.
  """

  require Logger

  @doc """
  Generates JSON-LD structured data for breadcrumbs.

  ## Parameters
    - breadcrumbs: A list of maps with `name` and `url` keys
    - base_url: Optional base URL for the site (defaults to configured endpoint)

  ## Returns
    - A JSON-LD string ready to be included in the page head

  ## Examples

      ```elixir
      breadcrumbs = [
        %{name: "Home", url: "/"},
        %{name: "United Kingdom", url: "/countries/united-kingdom"},
        %{name: "London", url: "/cities/london"},
        %{name: "The Red Lion", url: nil}
      ]

      json_ld = BreadcrumbSchema.generate_breadcrumb_json_ld(breadcrumbs)
      ```
  """
  def generate_breadcrumb_json_ld(breadcrumbs, base_url \\ nil) do
    # Format breadcrumbs as JSON-LD
    breadcrumb_data = %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => format_breadcrumb_items(breadcrumbs, base_url)
    }

    # Return the JSON-LD as a string with proper formatting
    Jason.encode!(breadcrumb_data)
  end

  @doc """
  Creates a breadcrumb list for a venue page.

  ## Parameters
    - venue: A venue struct with city and country preloaded
    - base_url: Optional base URL for the site

  ## Returns
    - A list of breadcrumb items with name and url keys
  """
  def create_venue_breadcrumbs(venue, _base_url \\ nil) do
    # Build the list of breadcrumbs
    breadcrumbs = [
      %{name: "Home", url: "/"}
    ]

    # Add country if available
    breadcrumbs = if venue.city && venue.city.country do
      country = venue.city.country
      breadcrumbs ++ [%{
        name: country.name,
        url: "/countries/#{country.slug || String.downcase(country.name) |> String.replace(~r/[^a-z0-9]+/, "-")}"
      }]
    else
      breadcrumbs
    end

    # Add city if available
    breadcrumbs = if venue.city do
      breadcrumbs ++ [%{
        name: venue.city.name,
        url: "/cities/#{venue.city.slug || String.downcase(venue.city.name) |> String.replace(~r/[^a-z0-9]+/, "-")}"
      }]
    else
      breadcrumbs
    end

    # Add venue (current page)
    breadcrumbs ++ [%{name: venue.name, url: nil}]
  end

  # Helper to format breadcrumb items as JSON-LD
  defp format_breadcrumb_items(breadcrumbs, base_url) do
    host_url = get_host_url(base_url)

    # Determine current page URL from the last breadcrumb (for last item)
    current_page_url = case List.last(breadcrumbs) do
      %{name: name} ->
        # Create a fallback URL for the current page based on the name
        path = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
        "#{host_url}/#{path}"
      _ ->
        "#{host_url}/"
    end

    breadcrumbs
    |> Enum.with_index(1)  # Start position at 1
    |> Enum.map(fn {item, position} ->
      # Get full URL for this item
      item_url = if item.url do
        if String.starts_with?(item.url, "http") do
          item.url
        else
          # Ensure URL has leading slash
          path = if String.starts_with?(item.url, "/"), do: item.url, else: "/#{item.url}"
          "#{host_url}#{path}"
        end
      else
        # For last item without URL, use the current page URL
        current_page_url
      end

      # Format according to Google's recommendations:
      # - name at ListItem level
      # - item as a URL string
      %{
        "@type" => "ListItem",
        "position" => position,
        "item" => %{
          "@id" => item_url,
          "name" => item.name
        }
      }
    end)
  end

  # Get the host URL from configuration or use the provided one
  defp get_host_url(nil) do
    url_config = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)[:url]
    scheme = url_config[:scheme] || "https"
    host = url_config[:host]
    port = url_config[:port]

    if port && port != 80 && port != 443 do
      "#{scheme}://#{host}:#{port}"
    else
      "#{scheme}://#{host}"
    end
  end
  defp get_host_url(base_url) when is_binary(base_url), do: base_url
end

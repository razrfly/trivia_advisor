defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Handles Google Places API lookups for venue addresses.
  """

  require Logger
  @http_client Application.compile_env(:trivia_advisor, :http_client, HTTPoison)

  @doc """
  Looks up a place_id using Google Places API.
  Returns {:ok, place_id} or {:error, reason}.
  """
  def lookup_address(address, opts \\ []) do
    with {:ok, api_key} <- get_api_key(),
         {:ok, place_data} <- find_place_from_text(address, api_key, opts) do
      case place_data do
        %{"place_id" => place_id} when is_binary(place_id) ->
          {:ok, place_id}
        _ ->
          {:error, :no_place_id}
      end
    end
  end

  defp get_api_key do
    case System.get_env("GOOGLE_MAPS_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp find_place_from_text(input, api_key, _opts) do
    params = %{
      input: input,
      inputtype: "textquery",
      fields: "place_id",
      key: api_key
    }

    case make_api_request(places_url(params)) do
      {:ok, response} -> handle_places_response(response)
      error -> error
    end
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => []}) do
    Logger.warning("No results found in Places API response")
    {:ok, %{}}
  end

  defp handle_places_response(%{"status" => "OK", "candidates" => [candidate | _]}) do
    {:ok, candidate}
  end

  defp handle_places_response(%{"status" => status, "error_message" => msg}) do
    Logger.error("Google Places API error: #{status} - #{msg}")
    {:error, msg}
  end

  defp places_url(params) do
    "https://maps.googleapis.com/maps/api/place/findplacefromtext/json?" <> URI.encode_query(params)
  end

  defp make_api_request(url) do
    case @http_client.get(url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} -> {:ok, response}
          {:error, error} ->
            Logger.error("Failed to decode API response: #{inspect(error)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("Google API HTTP #{status}")
        {:error, "HTTP #{status}"}

      {:error, error} ->
        Logger.error("API request failed: #{inspect(error)}")
        {:error, "Request failed"}
    end
  end
end

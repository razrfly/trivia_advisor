defmodule TriviaAdvisor.Scraping.GoogleLookup do
  @moduledoc """
  Module for looking up place data from Google Places and Geocoding APIs.
  """

  @base_url "https://maps.googleapis.com"
  @places_path "/maps/api/place"
  @geocoding_path "/maps/api/geocode/json"

  @doc """
  Looks up an address using Google Places API, falling back to Geocoding API if needed.
  """
  def lookup_address(address) when is_binary(address) do
    case find_place_from_text(address) do
      {:ok, %{"candidates" => [place | _]}} -> {:ok, place}
      {:ok, %{"candidates" => []}} -> lookup_geocode(address)
      error -> error
    end
  end

  @doc """
  Fetches detailed place data from Google Places API using a place_id.
  """
  def lookup_place_id(place_id) when is_binary(place_id) do
    params = %{
      place_id: place_id,
      key: api_key(),
      fields: "formatted_address,geometry,name,place_id,types"
    }

    "#{@base_url}#{@places_path}/details/json"
    |> HTTPoison.get([],
      params: params
    )
    |> handle_response()
  end

  @doc """
  Looks up address components and coordinates using Google Geocoding API.
  """
  def lookup_geocode(address) when is_binary(address) do
    params = %{
      address: address,
      key: api_key()
    }

    "#{@base_url}#{@geocoding_path}"
    |> HTTPoison.get([],
      params: params
    )
    |> handle_response()
  end

  # Private Functions

  defp find_place_from_text(input) do
    params = %{
      input: input,
      inputtype: "textquery",
      key: api_key(),
      fields: "formatted_address,geometry,name,place_id"
    }

    "#{@base_url}#{@places_path}/findplacefromtext/json"
    |> HTTPoison.get([],
      params: params
    )
    |> handle_response()
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, %{"status" => "OK"} = response} -> {:ok, response}
      {:ok, %{"status" => error}} -> {:error, error}
      error -> error
    end
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status}}) do
    {:error, "HTTP Status #{status}"}
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, reason}
  end

  defp api_key do
    Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI)[:google_maps_api_key]
  end
end

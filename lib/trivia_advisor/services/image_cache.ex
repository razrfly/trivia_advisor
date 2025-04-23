defmodule TriviaAdvisor.Services.ImageCache do
  @moduledoc """
  ETS-based cache for image URLs fetched from Unsplash API.
  """

  use GenServer
  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.City

  @table_name :unsplash_image_cache
  @cache_timeout 24 * 60 * 60 # 24 hours in seconds
  @api_fetch_timeout 10_000 # 10 seconds

  # Client API

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get venue image URL for the given venue name and type.
  Fetches from cache or Unsplash API if not found.
  """
  def get_venue_image(venue) do
    venue_type = determine_venue_type(venue)
    venue_id = extract_venue_id(venue)
    key = {:venue, venue_type, venue_id}

    case from_cache(key) do
      {:ok, url} -> url
      :error ->
        # Not in cache, fetch from API
        GenServer.call(__MODULE__, {:fetch_venue_image, venue, venue_type}, @api_fetch_timeout)
    end
  end

  @doc """
  Get city image with attribution data.
  Tries city database record first, falls back to Unsplash API.
  """
  def get_city_image_with_attribution(city) do
    city_name = extract_city_name(city)
    key = {:city, String.downcase(city_name)}

    case from_cache(key) do
      {:ok, {url, attribution}} -> {url, attribution}
      :error ->
        # Not in cache, try from database first, then API
        GenServer.call(__MODULE__, {:fetch_city_image, city}, @api_fetch_timeout)
    end
  end

  # Server Callbacks

  @impl true
  def init(_) do
    # Create ETS table for caching
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :named_table,
          :set,
          :protected,
          read_concurrency: true,
          write_concurrency: true
        ])
      tid when is_reference(tid) ->
        :ets.give_away(tid, self(), nil)
    end
    {:ok, %{}}
  end

  @impl true
  def handle_call({:fetch_venue_image, venue, venue_type}, _from, state) do
    venue_id = extract_venue_id(venue)
    search_term = get_search_term_for_venue_type(venue_type)
    key = {:venue, venue_type, venue_id}

    # Try to get image from unsplash API
    url = case fetch_from_unsplash_api(search_term) do
      {:ok, image_url} ->
        # Cache the result
        cache_result(key, image_url)
        image_url
      {:error, reason} ->
        Logger.warning("Failed to fetch venue image from Unsplash: #{inspect(reason)}")
        # Fallback to city images if available
        fallback_to_city_image(venue) || default_image_url()
    end

    {:reply, url, state}
  end

  @impl true
  def handle_call({:fetch_city_image, city}, _from, state) do
    city_name = extract_city_name(city)
    key = {:city, String.downcase(city_name)}

    # First try to get from database
    result = case fetch_city_image_from_database(city) do
      {:ok, url, attribution} ->
        # Cache the result
        cache_result(key, {url, attribution})
        {url, attribution}
      :error ->
        # Try Unsplash API
        case fetch_from_unsplash_api("city #{city_name}") do
          {:ok, image_url} ->
            attribution = %{
              "photographer_name" => "Unsplash",
              "unsplash_url" => "https://unsplash.com?utm_source=trivia_advisor&utm_medium=referral"
            }
            # Cache the result
            cache_result(key, {image_url, attribution})
            {image_url, attribution}
          {:error, reason} ->
            Logger.warning("Failed to fetch city image from Unsplash: #{inspect(reason)}")
            # Fallback to default
            {default_image_url(), %{"photographer_name" => "Default"}}
        end
    end

    {:reply, result, state}
  end

  # Private functions

  defp from_cache(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, timestamp}] ->
        # Check if cache is still valid
        if System.system_time(:second) - timestamp < @cache_timeout do
          {:ok, value}
        else
          # Expired, remove from cache
          :ets.delete(@table_name, key)
          :error
        end
      [] -> :error
    end
  end

  defp cache_result(key, value) do
    :ets.insert(@table_name, {key, value, System.system_time(:second)})
  end

  defp determine_venue_type(venue) do
    venue_name = extract_venue_name(venue)
    venue_name = String.downcase(venue_name || "")

    cond do
      String.contains?(venue_name, ["arms", "tavern", "tap", "inn"]) ||
      String.contains?(venue_name, ["pub", "alehouse", "brewery"]) ->
        :pub
      String.contains?(venue_name, ["bar", "lounge", "club", "room"]) ->
        :bar
      String.contains?(venue_name, ["hotel", "lodge", "house"]) ->
        :hotel
      true ->
        :generic
    end
  end

  defp extract_venue_id(venue) do
    cond do
      is_map(venue) && Map.has_key?(venue, :id) && venue.id ->
        venue.id
      is_map(venue) && Map.has_key?(venue, "id") && venue["id"] ->
        venue["id"]
      true ->
        nil
    end
  end

  defp extract_venue_name(venue) do
    cond do
      is_map(venue) && Map.has_key?(venue, :name) && venue.name ->
        venue.name
      is_map(venue) && Map.has_key?(venue, "name") && venue["name"] ->
        venue["name"]
      true ->
        ""
    end
  end

  defp extract_city_name(city) do
    cond do
      is_map(city) && Map.has_key?(city, :name) && city.name ->
        city.name
      is_map(city) && Map.has_key?(city, "name") && city["name"] ->
        city["name"]
      true ->
        "unknown"
    end
  end

  defp extract_city_id(city) do
    cond do
      is_map(city) && Map.has_key?(city, :id) && city.id ->
        city.id
      is_map(city) && Map.has_key?(city, "id") && city["id"] ->
        city["id"]
      true ->
        nil
    end
  end

  defp get_search_term_for_venue_type(:pub), do: "pub interior"
  defp get_search_term_for_venue_type(:bar), do: "bar interior"
  defp get_search_term_for_venue_type(:hotel), do: "hotel bar"
  defp get_search_term_for_venue_type(:generic), do: "pub quiz"
  defp get_search_term_for_venue_type(_), do: "pub interior"

  defp fetch_from_unsplash_api(search_term) do
    api_key = get_unsplash_api_key()

    if api_key == nil do
      {:error, "No Unsplash API key configured"}
    else
      url = "https://api.unsplash.com/photos/random?query=#{URI.encode(search_term)}&orientation=landscape&content_filter=high"

      headers = [
        {"Authorization", "Client-ID #{api_key}"},
        {"Accept-Version", "v1"}
      ]

      case HTTPoison.get(url, headers, [timeout: 5000, recv_timeout: 5000]) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              # Extract image URL and add UTM parameters for attribution
              image_url = data["urls"]["regular"]
              image_url = add_utm_params(image_url)
              {:ok, image_url}
            {:error, _} ->
              {:error, "Failed to parse Unsplash API response"}
          end
        {:ok, %{status_code: code}} ->
          {:error, "Unsplash API returned status #{code}"}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_city_image_from_database(city) do
    city_record = case extract_city_id(city) do
      nil ->
        case is_map(city) && Map.has_key?(city, :city) && city.city do
          true -> city.city  # Use the city relation if present
          _ -> fetch_city_by_name(extract_city_name(city))
        end
      id -> fetch_city_by_id(id)
    end

    case city_record do
      %{unsplash_gallery: gallery} when not is_nil(gallery) ->
        if gallery["images"] && is_list(gallery["images"]) && length(gallery["images"]) > 0 do
          # Get a random image from the gallery
          images = gallery["images"]
          image = Enum.random(images)

          if image["url"] do
            # Extract attribution if available
            attribution = if image["attribution"] do
              ensure_utm_parameters(image["attribution"])
            else
              %{"photographer_name" => "Unsplash", "unsplash_url" => "https://unsplash.com?utm_source=trivia_advisor&utm_medium=referral"}
            end

            {:ok, image["url"], attribution}
          else
            :error
          end
        else
          :error
        end
      _ ->
        :error
    end
  end

  defp fetch_city_by_id(id) do
    try do
      Repo.get(City, id)
    rescue
      _ -> nil
    end
  end

  defp fetch_city_by_name(name) do
    try do
      Repo.get_by(City, name: name)
    rescue
      _ -> nil
    end
  end

  defp fallback_to_city_image(venue) do
    # Check if we're inside the GenServer process to avoid recursive calls
    if self() == Process.whereis(__MODULE__) do
      # Already inside the server - call the private helper directly
      city = case is_map(venue) && Map.has_key?(venue, :city) && venue.city do
        true -> venue.city
        _ -> nil
      end

      case city do
        nil -> default_image_url()
        city ->
          case fetch_city_image_from_database(city) do
            {:ok, url, _attr} -> url
            :error -> default_image_url()
          end
      end
    else
      # External caller - safe to use public API
      case is_map(venue) && Map.has_key?(venue, :city) && venue.city do
        true ->
          {url, _} = get_city_image_with_attribution(venue.city)
          url
        _ ->
          default_image_url()
      end
    end
  end

  defp get_unsplash_api_key do
    Application.get_env(:trivia_advisor, :unsplash_api_key)
  end

  defp default_image_url do
    "/images/default-venue.jpg"
  end

  defp add_utm_params(url) do
    utm_params = "?utm_source=trivia_advisor&utm_medium=referral"

    if String.contains?(url, "?") do
      if String.contains?(url, "utm_source") do
        url
      else
        String.replace(url, "?", "#{utm_params}&")
      end
    else
      "#{url}#{utm_params}"
    end
  end

  defp ensure_utm_parameters(attribution) do
    utm_params = "?utm_source=trivia_advisor&utm_medium=referral"

    # Handle both string and atom keys
    photographer_url = Map.get(attribution, "photographer_url") || Map.get(attribution, :photographer_url)
    unsplash_url = Map.get(attribution, "unsplash_url") || Map.get(attribution, :unsplash_url)

    # Only update URLs if they exist and don't already have UTM params
    updated_attribution = attribution

    updated_attribution = if photographer_url && not String.contains?(photographer_url, "utm_source") do
      Map.put(updated_attribution, "photographer_url", "#{photographer_url}#{utm_params}")
    else
      updated_attribution
    end

    updated_attribution = if unsplash_url && not String.contains?(unsplash_url, "utm_source") do
      Map.put(updated_attribution, "unsplash_url", "#{unsplash_url}#{utm_params}")
    else
      updated_attribution
    end

    updated_attribution
  end
end

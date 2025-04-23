defmodule TriviaAdvisor.Services.UnsplashService do
  @moduledoc """
  Service for fetching images from Unsplash API and retrieving them from database.
  Uses the unsplash_gallery field in City and Country models instead of ETS caching.
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{City, Country}
  alias TriviaAdvisor.Services.UnsplashImageFetcher

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Get an image URL for a city, either from database or fetch from Unsplash API.
  """
  def get_city_image(city_name) do
    # Try to get from database first
    case get_image_from_db("city", city_name) do
      {:ok, image_data} ->
        image_data
      {:error, :not_found} ->
        # City not found in database
        Logger.warning("City not found: #{city_name}")
        nil
      {:error, :no_gallery} ->
        # Try to fetch and store images
        try do
          GenServer.call(__MODULE__, {:fetch_and_save_city_images, city_name})
        rescue
          e ->
            Logger.error("Error fetching city image for #{city_name}: #{inspect(e)}")
            nil
        catch
          :exit, reason ->
            Logger.error("GenServer call failed for city image #{city_name}: #{inspect(reason)}")
            nil
        end
    end
  end

  @doc """
  Get an image URL for a country, either from database or fetch from Unsplash API.
  Returns a map with the image URL and attribution data.
  """
  def get_country_image(country_name) do
    # Try to get from database first
    case get_image_from_db("country", country_name) do
      {:ok, image_data} ->
        image_data
      {:error, :not_found} ->
        # Country not found in database
        Logger.warning("Country not found: #{country_name}")
        %{image_url: nil, attribution: nil}
      {:error, :no_gallery} ->
        # Try to fetch and store images
        try do
          GenServer.call(__MODULE__, {:fetch_and_save_country_images, country_name})
        rescue
          e ->
            Logger.error("Error fetching country image for #{country_name}: #{inspect(e)}")
            %{image_url: nil, attribution: nil}
        catch
          :exit, reason ->
            Logger.error("GenServer call failed for country image #{country_name}: #{inspect(reason)}")
            %{image_url: nil, attribution: nil}
        end
    end
  end

  @doc """
  Get an image URL for a venue. For backwards compatibility.
  """
  def get_venue_image(_venue_name) do
    Logger.warning("get_venue_image/1 is deprecated and will return nil. Venue images are no longer supported.")
    nil
  end

  @doc """
  Clear the entire image cache. For backwards compatibility.
  """
  def clear_cache() do
    Logger.warning("clear_cache/0 is deprecated. Images are now stored in the database.")
    :ok
  end

  @doc """
  Clear cache for a specific type and name. For backwards compatibility.
  """
  def clear_cache(_type, _name) do
    Logger.warning("clear_cache/2 is deprecated. Images are now stored in the database.")
    :ok
  end

  @doc """
  Rotate to the next image in the gallery for a city.
  This cycles through the saved images without hitting the Unsplash API.
  """
  def rotate_city_image(city_name) do
    GenServer.call(__MODULE__, {:rotate_image, "city", city_name})
  end

  @doc """
  Rotate to the next image in the gallery for a country.
  This cycles through the saved images without hitting the Unsplash API.
  """
  def rotate_country_image(country_name) do
    GenServer.call(__MODULE__, {:rotate_image, "country", country_name})
  end

  @doc """
  Force a refresh of images for a country from Unsplash API.
  """
  def refresh_country_images(country_name) do
    GenServer.call(__MODULE__, {:refresh_country_images, country_name})
  end

  @doc """
  Force a refresh of images for a city from Unsplash API.
  """
  def refresh_city_images(city_name, country_name \\ nil) do
    GenServer.call(__MODULE__, {:refresh_city_images, city_name, country_name})
  end

  @doc """
  Get multiple city images in a batch to avoid N+1 query problem.
  Takes a list of city names and returns a map of {city_name => image_url}.
  """
  def get_city_images_batch(city_names) when is_list(city_names) do
    # Get all cities from database in a single query
    query = from c in City,
      where: c.name in ^city_names

    # Get all records in one query
    cities = Repo.all(query)

    # Create a map of city_name => record for quick access
    city_records = Enum.reduce(cities, %{}, fn city, acc ->
      Map.put(acc, city.name, city)
    end)

    # Process each city name and build the result map
    city_names
    |> Enum.reduce(%{}, fn city_name, acc ->
      case Map.get(city_records, city_name) do
        nil ->
          # City not in database, schedule fetching and return nil for now
          Task.start(fn ->
            # Try to fetch in background but don't wait for result
            _ = get_city_image(city_name)
          end)
          Map.put(acc, city_name, %{url: nil, image_url: nil})

        city ->
          gallery = city.unsplash_gallery

          cond do
            is_nil(gallery) || gallery == %{} ->
              # Gallery not present, schedule fetching and return nil for now
              Task.start(fn ->
                # Try to fetch in background but don't wait for result
                _ = get_city_image(city_name)
              end)
              Map.put(acc, city_name, %{url: nil, image_url: nil})

            is_nil(Map.get(gallery, "images")) || Enum.empty?(Map.get(gallery, "images", [])) ->
              # No images in gallery
              Map.put(acc, city_name, %{url: nil, image_url: nil})

            true ->
              # Get images and calculate the current index based on time and entity ID
              images = Map.get(gallery, "images")
              current_index = get_hourly_image_index(city.id, length(images))

              # Get current image URL
              image = Enum.at(images, current_index)
              url = if(is_nil(image), do: nil, else: image["url"])

              Map.put(acc, city_name, %{url: url, image_url: url})
          end
      end
    end)
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:fetch_and_save_country_images, country_name}, _from, state) do
    result = case UnsplashImageFetcher.fetch_and_store_country_images(country_name) do
      {:ok, _count} ->
        # Successfully fetched and stored images, now get the first one
        case get_image_from_db("country", country_name) do
          {:ok, image_data} -> image_data
          _ -> %{image_url: nil, attribution: nil}
        end
      {:error, _reason} ->
        %{image_url: nil, attribution: nil}
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:fetch_and_save_city_images, city_name}, _from, state) do
    result = case UnsplashImageFetcher.fetch_and_store_city_images(city_name) do
      {:ok, _count} ->
        # Successfully fetched and stored images, now get the first one
        case get_image_from_db("city", city_name) do
          {:ok, image_data} -> image_data
          _ -> nil
        end
      {:error, _reason} ->
        nil
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:rotate_image, type, name}, _from, state) do
    result = case rotate_db_image(type, name) do
      {:ok, image_data} -> image_data
      {:error, _reason} ->
        if type == "country", do: %{image_url: nil, attribution: nil}, else: nil
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:refresh_country_images, country_name}, _from, state) do
    result = UnsplashImageFetcher.fetch_and_store_country_images(country_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:refresh_city_images, city_name, _country_name}, _from, state) do
    result = UnsplashImageFetcher.fetch_and_store_city_images(city_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:fetch_city_images, city_name, opts}, _from, state) do
    # Queue a background job to refresh or fetch new images for the city
    if opts[:refresh] == true do
      # Refresh the cache immediately
      result = UnsplashImageFetcher.fetch_and_store_city_images(city_name)

      # Return the result of the fetch operation
      {:reply, result, state}
    else
      # Just fetch the existing images or get them from Unsplash if needed
      {:reply, get_city_image(city_name), state}
    end
  end

  @impl true
  def handle_call({:get_city_image, city_name}, _from, state) do
    {:reply, get_city_image(city_name), state}
  end

  @impl true
  def handle_call({:get_country_image, country_name}, _from, state) do
    {:reply, get_country_image(country_name), state}
  end

  @impl true
  def handle_call({:rotate_city_image, city_name}, _from, state) do
    {:reply, rotate_city_image(city_name), state}
  end

  @impl true
  def handle_call({:rotate_country_image, country_name}, _from, state) do
    {:reply, rotate_country_image(country_name), state}
  end

  @impl true
  def handle_call({:fetch_city_image, city_name, _country_name}, _from, state) do
    result = UnsplashImageFetcher.fetch_and_store_city_images(city_name)
    {:reply, result, state}
  end

  # Private functions

  @doc """
  Calculate the current image index based on time and entity ID.
  This provides a deterministic but time-varying index that changes hourly
  and provides variety between different entities.
  """
  def get_hourly_image_index(entity_id, total_images \\ 15) do
    # Get current hour (0-23)
    current_hour = DateTime.utc_now().hour

    # Get day of year (1-366) for variety between days
    day_of_year = Date.day_of_year(Date.utc_today())

    # Mix entity ID to create variety between different entities
    # Use a prime number multiplier to increase "randomness"
    entity_factor = rem(entity_id * 7, total_images)

    # Calculate the index - wrapping around if needed
    rem(current_hour + day_of_year + entity_factor, total_images)
  end

  defp get_image_from_db(type, name) do
    # Normalize name to ensure consistency
    name = String.trim(name)

    # Find the record in the database
    record = case type do
      "city" ->
        Repo.get_by(City, name: name)
      "country" ->
        Repo.get_by(Country, name: name)
      _ ->
        nil
    end

    if is_nil(record) do
      {:error, :not_found}
    else
      gallery = Map.get(record, :unsplash_gallery)

      if is_nil(gallery) || gallery == %{} || is_nil(Map.get(gallery, "images")) || Enum.empty?(Map.get(gallery, "images")) do
        {:error, :no_gallery}
      else
        # Get image data from the gallery using hourly rotation
        images = Map.get(gallery, "images")

        # Get entity ID from record for use in rotation
        entity_id = record.id

        # Calculate the current index based on time and entity ID
        current_index = get_hourly_image_index(entity_id, length(images))

        # Get the current image
        current_image = Enum.at(images, current_index)

        # Return the image data
        url = Map.get(current_image, "url")
        attribution = Map.get(current_image, "attribution")

        # Format the response based on type
        result = if type == "country" do
          %{image_url: url, attribution: attribution}
        else
          %{url: url, attribution: attribution, image_url: url}
        end

        {:ok, result}
      end
    end
  end

  # Define the function with defaults in the header
  defp rotate_db_image(type, name, format_fn \\ &(&1))

  # Type-specific implementations
  defp rotate_db_image("country", country_name, _format_fn) do
    # For backwards compatibility
    rotate_db_image("country", country_name, fn image ->
      %{image_url: image["url"], attribution: image["attribution"]}
    end)
  end

  defp rotate_db_image("city", city_name, _format_fn) do
    # For backwards compatibility
    rotate_db_image("city", city_name, fn image -> image["url"] end)
  end

  # Generic implementation
  defp rotate_db_image(type, name, format_fn) when type in ["country", "city"] do
    # Get the record
    record = case type do
      "country" -> Repo.get_by(Country, name: name)
      "city" -> Repo.get_by(City, name: name)
    end

    if is_nil(record) do
      {:error, :not_found}
    else
      gallery = Map.get(record, :unsplash_gallery)

      if is_nil(gallery) do
        {:error, :no_gallery}
      else
        images = Map.get(gallery, "images", [])

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          # Force a "rotation" by using a different hour than the current one
          next_hour = rem(DateTime.utc_now().hour + 1, 24)
          day_of_year = Date.day_of_year(Date.utc_today())
          entity_factor = rem(record.id * 7, length(images))

          # Calculate next index as if it were the next hour
          next_index = rem(next_hour + day_of_year + entity_factor, length(images))

          # Get the image at the forced "next hour" index
          new_image = Enum.at(images, next_index)

          # Return the result formatted appropriately
          {:ok, format_fn.(new_image)}
        end
      end
    end
  end
end

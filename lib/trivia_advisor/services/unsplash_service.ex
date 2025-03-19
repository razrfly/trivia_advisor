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
  def handle_call({:refresh_city_images, city_name, country_name}, _from, state) do
    result = UnsplashImageFetcher.fetch_and_store_city_images(city_name, country_name)
    {:reply, result, state}
  end

  # Private functions

  defp get_image_from_db("country", country_name) do
    query = from c in Country,
      where: c.name == ^country_name,
      select: c.unsplash_gallery

    case Repo.one(query) do
      nil ->
        {:error, :not_found}
      gallery when is_nil(gallery) ->
        {:error, :no_gallery}
      gallery ->
        # Get the current image from the gallery
        images = Map.get(gallery, "images", [])
        current_index = Map.get(gallery, "current_index", 0)

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          # Use the current index to get the right image
          current_index = min(current_index, length(images) - 1)
          image = Enum.at(images, current_index)

          # Format the response for compatibility with existing code
          {:ok, %{
            image_url: image["url"],
            attribution: image["attribution"]
          }}
        end
    end
  end

  defp get_image_from_db("city", city_name) do
    query = from c in City,
      where: c.name == ^city_name,
      select: c.unsplash_gallery

    case Repo.one(query) do
      nil ->
        {:error, :not_found}
      gallery when is_nil(gallery) ->
        {:error, :no_gallery}
      gallery ->
        # Get the current image from the gallery
        images = Map.get(gallery, "images", [])
        current_index = Map.get(gallery, "current_index", 0)

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          # Use the current index to get the right image
          current_index = min(current_index, length(images) - 1)
          image = Enum.at(images, current_index)

          # Return the image URL for compatibility with existing code
          {:ok, image["url"]}
        end
    end
  end

  defp rotate_db_image("country", country_name) do
    # Get the country record
    country = Repo.get_by(Country, name: country_name)

    if is_nil(country) do
      {:error, :not_found}
    else
      gallery = country.unsplash_gallery

      if is_nil(gallery) do
        {:error, :no_gallery}
      else
        images = Map.get(gallery, "images", [])
        current_index = Map.get(gallery, "current_index", 0)

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          # Calculate the next index (wrap around if needed)
          next_index = rem(current_index + 1, length(images))

          # Update the gallery with the new index
          updated_gallery = Map.put(gallery, "current_index", next_index)

          # Update the database
          {:ok, _updated} = Repo.update(
            Country.changeset(country, %{unsplash_gallery: updated_gallery})
          )

          # Return the new current image
          new_image = Enum.at(updated_gallery["images"], next_index)

          {:ok, %{
            image_url: new_image["url"],
            attribution: new_image["attribution"]
          }}
        end
      end
    end
  end

  defp rotate_db_image("city", city_name) do
    # Get the city record
    city = Repo.get_by(City, name: city_name)

    if is_nil(city) do
      {:error, :not_found}
    else
      gallery = city.unsplash_gallery

      if is_nil(gallery) do
        {:error, :no_gallery}
      else
        images = Map.get(gallery, "images", [])
        current_index = Map.get(gallery, "current_index", 0)

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          # Calculate the next index (wrap around if needed)
          next_index = rem(current_index + 1, length(images))

          # Update the gallery with the new index
          updated_gallery = Map.put(gallery, "current_index", next_index)

          # Update the database
          {:ok, _updated} = Repo.update(
            City.changeset(city, %{unsplash_gallery: updated_gallery})
          )

          # Return the new current image URL
          new_image = Enum.at(updated_gallery["images"], next_index)

          {:ok, new_image["url"]}
        end
      end
    end
  end
end

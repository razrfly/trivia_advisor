defmodule TriviaAdvisor.Services.UnsplashImageFetcher do
  @moduledoc """
  Service for fetching and storing Unsplash image galleries in the database.
  Stores multiple images per city or country to reduce API calls.
  """

  require Logger
  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{City, Country}
  import Ecto.Query

  @max_images 10 # Number of images to store per location

  @doc """
  Fetch and store images for a country.
  Returns {:ok, images_count} or {:error, reason}.
  """
  def fetch_and_store_country_images(country_name) do
    case get_country_by_name(country_name) do
      nil ->
        Logger.error("Country not found: #{country_name}")
        {:error, :not_found}

      country ->
        Logger.info("Fetching images for country: #{country_name}")
        case fetch_unsplash_images("country", country_name) do
          {:ok, images} ->
            gallery = %{
              "images" => images,
              "last_refreshed" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "current_index" => 0
            }

            result = Repo.update(
              Country.changeset(country, %{unsplash_gallery: gallery})
            )

            case result do
              {:ok, _updated} ->
                Logger.info("Stored #{length(images)} images for country: #{country_name}")
                {:ok, length(images)}
              {:error, changeset} ->
                Logger.error("Failed to update country: #{inspect(changeset.errors)}")
                {:error, changeset}
            end

          {:error, reason} ->
            Logger.error("Failed to fetch images for country #{country_name}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Fetch and store images for a city.
  Returns {:ok, images_count} or {:error, reason}.
  """
  def fetch_and_store_city_images(city_name, country_name \\ nil) do
    city_query = if country_name do
      # If country name is provided, use it to narrow down the search
      from(c in City,
        join: country in assoc(c, :country),
        where: c.name == ^city_name and country.name == ^country_name,
        preload: [:country])
    else
      from(c in City,
        where: c.name == ^city_name,
        preload: [:country])
    end

    case Repo.one(city_query) do
      nil ->
        Logger.error("City not found: #{city_name}")
        {:error, :not_found}

      city ->
        Logger.info("Fetching images for city: #{city_name}" <> if country_name, do: " in #{country_name}", else: "")
        search_term = "#{city_name} #{city.country.name} city"

        case fetch_unsplash_images("city", search_term) do
          {:ok, images} ->
            gallery = %{
              "images" => images,
              "last_refreshed" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "current_index" => 0
            }

            result = Repo.update(
              City.changeset(city, %{unsplash_gallery: gallery})
            )

            case result do
              {:ok, _updated} ->
                Logger.info("Stored #{length(images)} images for city: #{city_name}")
                {:ok, length(images)}
              {:error, changeset} ->
                Logger.error("Failed to update city: #{inspect(changeset.errors)}")
                {:error, changeset}
            end

          {:error, reason} ->
            Logger.error("Failed to fetch images for city #{city_name}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Fetch images from Unsplash for a given type and name.
  Returns {:ok, images_list} or {:error, reason}.
  """
  def fetch_unsplash_images(type, name) do
    # Get API key from environment
    case System.get_env("UNSPLASH_ACCESS_KEY") do
      nil ->
        Logger.warning("UNSPLASH_ACCESS_KEY not set. Using fallback images.")
        {:ok, generate_fallback_images(name)}

      access_key ->
        # Customize search query based on type
        query = case type do
          "city" -> "#{name} city"
          "country" -> "#{name} landscape picturesque"
          _ -> name
        end

        # Use search endpoint instead of random for more relevant results
        # Reduce per_page from 30 to 15 to reduce the likelihood of hitting rate limits
        url = "https://api.unsplash.com/search/photos?query=#{URI.encode(query)}&orientation=landscape&per_page=15&client_id=#{access_key}"

        Logger.info("Fetching images from Unsplash for #{type}: #{name}")

        # Try to fetch with backoff on rate limiting
        fetch_with_backoff(url, type, name, 1)
    end
  end

  @doc """
  Generate a list of fallback images when Unsplash API is unavailable
  """
  def generate_fallback_images(name) do
    # Generate a deterministic set of fallback images based on the name
    letter = String.downcase(String.first(name)) |> String.to_charlist() |> hd()

    # Create 5 different fallback images (a smaller set than the usual 10)
    Enum.map(1..5, fn i ->
      seed = rem(letter - 97 + i, 5) + 1  # Cycle through 5 different images

      url = case seed do
        1 -> "https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=1200"
        2 -> "https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=1200"
        3 -> "https://images.unsplash.com/photo-1444723121867-7a241cacace9?w=1200"
        4 -> "https://images.unsplash.com/photo-1449824913935-59a10b8d2000?w=1200"
        _ -> "https://images.unsplash.com/photo-1514924013411-cbf25faa35bb?w=1200"
      end

      %{
        "id" => "fallback-#{seed}",
        "url" => url,
        "thumb_url" => url,
        "download_url" => nil,
        "color" => "#000000",
        "width" => 1200,
        "height" => 800,
        "attribution" => %{
          "photographer_name" => "Fallback Image",
          "photographer_username" => "trivia_advisor",
          "photographer_url" => nil,
          "unsplash_url" => "https://unsplash.com"
        },
        "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    end)
  end

  # Private helpers

  defp get_country_by_name(name) do
    Repo.get_by(Country, name: name)
  end

  # Private helper to implement backoff and retry
  defp fetch_with_backoff(url, type, name, attempt) do
    max_attempts = 3

    if attempt > max_attempts do
      Logger.error("Max retry attempts reached for #{type}: #{name}")
      {:error, :max_retries_exceeded}
    else
      case HTTPoison.get(url, [], [follow_redirect: true]) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              # Get the results
              results = Map.get(data, "results", [])

              if length(results) > 0 do
                # Sort by likes (highest first) and take top 10 (or less if fewer results)
                images = results
                |> Enum.sort_by(fn r -> Map.get(r, "likes", 0) end, :desc)
                |> Enum.take(@max_images)
                |> Enum.map(fn result ->
                  %{
                    "id" => get_in(result, ["id"]),
                    "url" => get_in(result, ["urls", "regular"]),
                    "thumb_url" => get_in(result, ["urls", "thumb"]),
                    "download_url" => get_in(result, ["links", "download"]),
                    "color" => get_in(result, ["color"]),
                    "width" => get_in(result, ["width"]),
                    "height" => get_in(result, ["height"]),
                    "attribution" => %{
                      "photographer_name" => get_in(result, ["user", "name"]),
                      "photographer_username" => get_in(result, ["user", "username"]),
                      "photographer_url" => get_in(result, ["user", "links", "html"]),
                      "unsplash_url" => "#{get_in(result, ["links", "html"])}?utm_source=trivia_advisor&utm_medium=referral"
                    },
                    "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                  }
                end)

                {:ok, images}
              else
                Logger.warning("No image results for #{name}")
                {:ok, generate_fallback_images(name)}
              end
            error ->
              Logger.error("Failed to parse Unsplash API response: #{inspect(error)}")
              {:error, :parse_error}
          end

        {:ok, %{status_code: 403, body: body}} ->
          if String.contains?(body, "Rate Limit Exceeded") do
            # Implement exponential backoff
            backoff_time = :math.pow(3, attempt) * 1000 |> round()
            Logger.warning("Unsplash API rate limit exceeded for #{type} #{name}. Retrying in #{backoff_time/1000} seconds (attempt #{attempt}/#{max_attempts})")

            # Sleep for the backoff time
            Process.sleep(backoff_time)

            # Retry with increased attempt count
            fetch_with_backoff(url, type, name, attempt + 1)
          else
            Logger.error("Access forbidden: #{body}")
            {:error, :forbidden}
          end

        {:ok, %{status_code: 429}} ->
          # 429 Too Many Requests - implement backoff
          backoff_time = :math.pow(3, attempt) * 1000 |> round()
          Logger.warning("Unsplash API rate limit exceeded (429) for #{type} #{name}. Retrying in #{backoff_time/1000} seconds (attempt #{attempt}/#{max_attempts})")

          Process.sleep(backoff_time)
          fetch_with_backoff(url, type, name, attempt + 1)

        error ->
          Logger.error("Unsplash API request failed: #{inspect(error)}")
          {:error, :api_error}
      end
    end
  end
end

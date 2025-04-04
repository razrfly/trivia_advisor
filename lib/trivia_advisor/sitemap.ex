defmodule TriviaAdvisor.Sitemap do
  @moduledoc """
  Generates XML sitemaps for the TriviaAdvisor website.
  Uses Sitemapper to generate sitemaps for cities and venues.
  """

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{City, Venue}
  import Ecto.Query, only: [from: 2]
  require Logger

  @doc """
  Generates and persists a sitemap for the website.
  This includes all cities and venues.

  Returns :ok on success or {:error, reason} on failure.
  """
  def generate_and_persist do
    try do
      # Ensure environment variables are loaded
      load_env_vars()

      # Get the sitemap configuration
      config = get_sitemap_config()

      # Log start of generation
      Logger.info("Starting sitemap generation")

      # Use a database transaction to ensure proper streaming
      Repo.transaction(fn ->
        stream_urls()
        |> Sitemapper.generate(config)
        |> Sitemapper.persist(config)
        |> Stream.run()
      end)

      Logger.info("Sitemap generation completed")
      :ok
    rescue
      error ->
        Logger.error("Sitemap generation failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a stream of URLs for the sitemap.
  """
  def stream_urls do
    # Combine all streams
    [homepage_urls(), city_urls(), venue_urls()]
    |> Enum.reduce(Stream.concat([]), fn stream, acc ->
      Stream.concat(acc, stream)
    end)
  end

  # Returns a stream of the main pages
  defp homepage_urls do
    # Create a list with the homepage URLs
    [
      %Sitemapper.URL{
        loc: get_base_url(),
        changefreq: :weekly,
        priority: 1.0,
        lastmod: Date.utc_today()
      },
      %Sitemapper.URL{
        loc: "#{get_base_url()}/cities",
        changefreq: :weekly,
        priority: 0.9,
        lastmod: Date.utc_today()
      }
    ]
    |> Stream.map(& &1)  # Convert to stream
  end

  # Returns a stream of all cities
  defp city_urls do
    # Get all cities with their last updated time
    from(c in City,
      select: %{slug: c.slug, updated_at: c.updated_at}
    )
    |> Repo.stream()
    |> Stream.map(fn city ->
      %Sitemapper.URL{
        loc: "#{get_base_url()}/cities/#{city.slug}",
        changefreq: :daily,
        priority: 0.8,
        lastmod: NaiveDateTime.to_date(city.updated_at)
      }
    end)
  end

  # Returns a stream of all venues
  defp venue_urls do
    # Get all venues with their last updated time
    from(v in Venue,
      select: %{slug: v.slug, updated_at: v.updated_at}
    )
    |> Repo.stream()
    |> Stream.map(fn venue ->
      %Sitemapper.URL{
        loc: "#{get_base_url()}/venues/#{venue.slug}",
        changefreq: :daily,
        priority: 0.7,
        lastmod: NaiveDateTime.to_date(venue.updated_at)
      }
    end)
  end

  # Get the base URL for the site
  defp get_base_url do
    host = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)[:url][:host]
    scheme = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)[:url][:scheme] || "https"
    "#{scheme}://#{host}"
  end

  # Get the sitemap configuration
  defp get_sitemap_config do
    # Get base URL
    base_url = get_base_url()

    # Determine if we're in production environment
    is_prod = Application.get_env(:trivia_advisor, :environment) == :prod

    # For local development, use FileStore
    # For production, use S3Store with Tigris credentials
    if is_prod do
      # Get bucket name from env, checking both Tigris and AWS variables
      bucket = System.get_env("TIGRIS_BUCKET_NAME") ||
               System.get_env("BUCKET_NAME") ||
               Application.get_env(:waffle, :bucket) ||
               "trivia-app"

      # Get region (default to auto if not specified)
      region = System.get_env("AWS_REGION") || "auto"

      # Get credentials, checking Tigris first, then AWS
      tigris_key = System.get_env("TIGRIS_ACCESS_KEY_ID")
      aws_key = System.get_env("AWS_ACCESS_KEY_ID")
      tigris_secret = System.get_env("TIGRIS_SECRET_ACCESS_KEY")
      aws_secret = System.get_env("AWS_SECRET_ACCESS_KEY")

      # Debug log the credential availability
      Logger.debug("Credentials check - Tigris key: #{!is_nil(tigris_key)}, AWS key: #{!is_nil(aws_key)}")
      Logger.debug("Credentials check - Tigris secret: #{!is_nil(tigris_secret)}, AWS secret: #{!is_nil(aws_secret)}")

      access_key_id = tigris_key || aws_key
      secret_access_key = tigris_secret || aws_secret

      # Ensure credentials are available
      if is_nil(access_key_id) || is_nil(secret_access_key) do
        Logger.error("Missing S3 credentials - access_key_id: #{!is_nil(access_key_id)}, secret_access_key: #{!is_nil(secret_access_key)}")
        raise "Missing required S3 credentials. Please set TIGRIS_ACCESS_KEY_ID/TIGRIS_SECRET_ACCESS_KEY or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY environment variables."
      end

      # Directly configure ExAws for Tigris
      Application.put_env(:ex_aws, :access_key_id, access_key_id)
      Application.put_env(:ex_aws, :secret_access_key, secret_access_key)

      # Configure S3 endpoint for Tigris
      Application.put_env(:ex_aws, :s3,
        %{
          host: "fly.storage.tigris.dev",
          scheme: "https://",
          region: region
        }
      )

      # Define path for sitemaps (store in sitemaps/ directory)
      sitemap_path = "sitemaps"

      # Add additional S3 object properties
      extra_props = [
        {:acl, :public_read},  # Make sitemaps publicly readable
        {:content_type, "application/xml"} # Set correct content type
      ]

      # Log the final configuration details
      Logger.debug("Sitemap config - S3Store, bucket: #{bucket}, path: #{sitemap_path}, region: #{region}")

      # Configure sitemap to store on S3
      [
        store: Sitemapper.S3Store,
        store_config: [
          bucket: bucket,
          region: region,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key,
          path: sitemap_path,
          extra_props: extra_props
        ],
        sitemap_url: "#{base_url}/#{sitemap_path}"
      ]
    else
      # For local development, use file storage
      priv_dir = :code.priv_dir(:trivia_advisor)
      sitemap_path = Path.join([priv_dir, "static", "sitemaps"])

      # Ensure directory exists
      File.mkdir_p!(sitemap_path)

      Logger.debug("Sitemap config - FileStore, path: #{sitemap_path}")

      # Return file store config
      [
        store: Sitemapper.FileStore,
        store_config: [path: sitemap_path],
        sitemap_url: "#{base_url}/sitemaps"
      ]
    end
  end

  # Load environment variables from .env file
  defp load_env_vars do
    case Code.ensure_loaded(DotenvParser) do
      {:module, _} ->
        Logger.debug("Loading environment variables from .env file")
        DotenvParser.load_file(".env")
      _ ->
        Logger.warning("DotenvParser module not found. Assuming environment variables are already loaded.")
    end
  end
end

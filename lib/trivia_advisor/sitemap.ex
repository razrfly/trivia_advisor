defmodule TriviaAdvisor.Sitemap do
  @moduledoc """
  Generates XML sitemaps for the TriviaAdvisor website.
  Uses Sitemapper to generate sitemaps for cities and venues.
  """

  alias TriviaAdvisor.Repo
  alias TriviaAdvisor.Locations.{City, Venue}
  alias TriviaAdvisor.Events.{Event, EventSource}
  import Ecto.Query
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
        # Get the stream of URLs and count them
        url_stream = stream_urls()

        # Log URL count before generating sitemap (for debugging)
        url_count = Enum.count(url_stream)
        Logger.info("Generated #{url_count} URLs for sitemap")

        if url_count == 0 do
          Logger.warning("No URLs generated for sitemap! Check your database content.")
          :ok
        else
          # Create a fresh stream for actual generation
          stream_urls()
          |> tap(fn _ -> Logger.info("Starting sitemap file generation") end)
          |> Sitemapper.generate(config)
          |> tap(fn stream ->
            # Log the first few items in the stream for debugging
            first_items = stream |> Enum.take(2)
            Logger.info("Generated #{length(first_items)} sitemap files: #{inspect(Enum.map(first_items, fn {filename, _} -> filename end))}")
          end)
          |> tap(fn _ -> Logger.info("Starting S3 upload of sitemap files") end)
          |> Sitemapper.persist(config)
          |> tap(fn _ -> Logger.info("Completed S3 upload of sitemap files") end)
          |> Stream.run()
        end
      end)

      Logger.info("Sitemap generation completed")
      :ok
    rescue
      error ->
        Logger.error("Sitemap generation failed: #{inspect(error, pretty: true)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace()}")
        {:error, error}
    catch
      kind, reason ->
        Logger.error("Caught #{kind} in sitemap generation: #{inspect(reason, pretty: true)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        {:error, reason}
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
    # Join venues with events and event_sources to get the latest last_seen_at
    # for each venue in a single query
    query = from v in Venue,
      left_join: e in Event, on: e.venue_id == v.id,
      left_join: es in EventSource, on: es.event_id == e.id,
      group_by: [v.id, v.slug, v.updated_at],
      select: %{
        id: v.id,
        slug: v.slug,
        updated_at: v.updated_at,
        # Get the maximum last_seen_at for this venue's events
        latest_event_timestamp: fragment("MAX(?)", es.last_seen_at)
      }

    query
    |> Repo.stream()
    |> Stream.map(fn venue_data ->
      # Determine the best timestamp to use
      lastmod = if venue_data.latest_event_timestamp do
        # Use the latest event source timestamp
        timestamp = NaiveDateTime.to_date(venue_data.latest_event_timestamp)
        Logger.debug("Venue #{venue_data.id} (#{venue_data.slug}) using event_source timestamp: #{Date.to_string(timestamp)}")
        timestamp
      else
        # Fallback to venue's updated_at
        timestamp = NaiveDateTime.to_date(venue_data.updated_at)
        Logger.debug("Venue #{venue_data.id} (#{venue_data.slug}) using venue updated_at: #{Date.to_string(timestamp)}")
        timestamp
      end

      %Sitemapper.URL{
        loc: "#{get_base_url()}/venues/#{venue_data.slug}",
        changefreq: :daily,
        priority: 0.7,
        lastmod: lastmod
      }
    end)
  end

  # Get the base URL for the sitemap
  defp get_base_url do
    # Use TriviaAdvisorWeb.Endpoint configuration
    endpoint_config = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)
    url_config = endpoint_config[:url]
    host = url_config[:host]
    port = url_config[:port]
    scheme = url_config[:scheme] || "https"

    is_prod = Application.get_env(:trivia_advisor, :environment) == :prod

    # For production, check PHX_HOST env var as a backup in case config is not properly set
    prod_host = if is_prod do
      System.get_env("PHX_HOST") || host || "quizadvisor.com"
    else
      host
    end

    base_url = cond do
      # In production, use the configured host directly
      is_prod ->
        "#{scheme}://#{prod_host}"

      # In development with non-standard port
      port && port != 80 && port != 443 ->
        "#{scheme}://#{host}:#{port}"

      # In development with standard port
      true ->
        "#{scheme}://#{host}"
    end

    Logger.debug("Base URL for sitemap: #{base_url}")
    base_url
  end

  # Get the sitemap configuration
  defp get_sitemap_config do
    # Get base URL
    base_url = get_base_url()

    # Determine if we're in production environment
    is_prod = Application.get_env(:trivia_advisor, :environment) == :prod
    Logger.debug("Environment: #{if is_prod, do: "production", else: "development"}")

    # For local development, use FileStore
    # For production, use S3Store with Tigris credentials
    if is_prod do
      # Get bucket name from env, checking both Tigris and AWS variables
      tigris_bucket = System.get_env("TIGRIS_BUCKET_NAME")
      aws_bucket = System.get_env("BUCKET_NAME")
      waffle_bucket = Application.get_env(:waffle, :bucket)

      Logger.debug("Available buckets - Tigris: #{inspect(tigris_bucket)}, AWS: #{inspect(aws_bucket)}, Waffle: #{inspect(waffle_bucket)}")

      bucket = tigris_bucket || aws_bucket || waffle_bucket || "trivia-app"

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
        error_msg = "Missing S3 credentials - access_key_id: #{!is_nil(access_key_id)}, secret_access_key: #{!is_nil(secret_access_key)}"
        Logger.error(error_msg)
        raise error_msg
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
      Logger.info("Sitemap config - S3Store, bucket: #{bucket}, path: #{sitemap_path}, region: #{region}")

      # For S3, the sitemap_url should be the public URL of the S3 bucket
      # This is where search engines will fetch the sitemap from
      _sitemap_host = "#{bucket}.fly.storage.tigris.dev"

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
        # For search engines, the sitemap should be accessible via the site's domain
        # not the S3 bucket URL
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
        Logger.debug("Checking for .env file")
        if File.exists?(".env") do
          Logger.debug("Loading environment variables from .env file")
          DotenvParser.load_file(".env")
        else
          Logger.debug("No .env file found, using system environment variables")
          :ok
        end
      _ ->
        Logger.warning("DotenvParser module not found. Using system environment variables.")
        :ok
    end
  end

  @doc """
  Test S3 connectivity with current credentials.
  This is useful for debugging S3 access issues.
  """
  def test_s3_connectivity do
    # Ensure environment variables are loaded
    load_env_vars()

    # Get the sitemap configuration to load credentials
    config = get_sitemap_config()

    # Extract store config
    store_config = config[:store_config]

    # Test connectivity
    bucket = store_config[:bucket]
    Logger.info("Testing S3 connectivity to bucket: #{bucket}")

    # Configure AWS directly
    Application.put_env(:ex_aws, :access_key_id, store_config[:access_key_id])
    Application.put_env(:ex_aws, :secret_access_key, store_config[:secret_access_key])

    # Configure S3 endpoint for Tigris
    Application.put_env(:ex_aws, :s3, %{
      host: "fly.storage.tigris.dev",
      scheme: "https://",
      region: store_config[:region]
    })

    # Try to list objects in the bucket
    case ExAws.S3.list_objects(bucket, max_keys: 5) |> ExAws.request() do
      {:ok, response} ->
        # Log successful response
        object_count = length(response.body.contents || [])
        Logger.info("S3 connection successful. Found #{object_count} objects in bucket.")
        Logger.debug("S3 response: #{inspect(response, pretty: true)}")
        {:ok, response}

      {:error, error} ->
        # Log error
        Logger.error("S3 connection failed: #{inspect(error, pretty: true)}")
        {:error, error}
    end
  end
end

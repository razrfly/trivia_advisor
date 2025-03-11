defmodule Mix.Tasks.SyncDb do
  @moduledoc """
  Syncs the local development database with the production database from Supabase.
  Also syncs uploaded files from Tigris cloud storage to local development.

  This task:
  1. Resets the local database using `mix ecto.reset`
  2. Downloads the production database from Supabase using the SUPABASE_DATABASE_URL from .env
  3. Imports the downloaded database into the local environment
  4. Deletes existing files in priv/static/uploads
  5. Downloads all files from Tigris cloud storage and stores them locally

  ## Examples

      mix sync_db

  """
  use Mix.Task
  require Logger

  @shortdoc "Syncs local database with production Supabase database and files from Tigris"
  @uploads_dir "priv/static/uploads"

  @impl Mix.Task
  def run(_args) do
    # Load environment variables from .env file
    load_env_vars()

    # Get the Supabase database URL from environment variables
    supabase_db_url = System.get_env("SUPABASE_DATABASE_URL")

    if is_nil(supabase_db_url) do
      Logger.error("SUPABASE_DATABASE_URL environment variable not found. Make sure it's set in your .env file.")
      exit({:shutdown, 1})
    end

    # Get Tigris credentials from environment variables
    tigris_access_key_id = System.get_env("TIGRIS_ACCESS_KEY_ID")
    tigris_secret_access_key = System.get_env("TIGRIS_SECRET_ACCESS_KEY")
    tigris_bucket_name = System.get_env("TIGRIS_BUCKET_NAME") || "trivia-app"

    if is_nil(tigris_access_key_id) || is_nil(tigris_secret_access_key) do
      Logger.error("Tigris credentials not found in .env file. Make sure TIGRIS_ACCESS_KEY_ID and TIGRIS_SECRET_ACCESS_KEY are set.")
      exit({:shutdown, 1})
    end

    # Parse the database URL to extract connection details
    db_config = parse_db_url(supabase_db_url)

    # Verify the hostname is resolvable
    verify_hostname(db_config.hostname)

    # Create a temporary directory for database dumps
    tmp_dir = Path.join(System.tmp_dir(), "trivia_advisor_db_sync")
    File.mkdir_p!(tmp_dir)
    dump_file = Path.join(tmp_dir, "production_dump.sql")

    try do
      # Step 1: Reset the local database
      Logger.info("Resetting local database...")
      {_, 0} = System.cmd("mix", ["ecto.reset"], into: IO.stream(:stdio, :line))

      # Step 2: Download the production database
      Logger.info("Downloading production database from Supabase...")
      download_production_db(db_config, dump_file)

      # Step 3: Import the downloaded database into local environment
      Logger.info("Importing production database into local environment...")
      import_database(dump_file)

      # Step 4: Sync files from Tigris to local storage
      Logger.info("Syncing files from Tigris cloud storage...")
      sync_files_from_tigris(tigris_access_key_id, tigris_secret_access_key, tigris_bucket_name)

      Logger.info("Database and file sync completed successfully!")
    rescue
      e ->
        Logger.error("Error syncing database or files: #{inspect(e)}")
        exit({:shutdown, 1})
    after
      # Clean up temporary files
      File.rm_rf!(tmp_dir)
    end
  end

  defp load_env_vars do
    case Code.ensure_loaded(DotenvParser) do
      {:module, _} ->
        DotenvParser.load_file(".env")
      _ ->
        Logger.warning("DotenvParser module not found. Assuming environment variables are already loaded.")
    end
  end

  defp parse_db_url(url) do
    # Parse PostgreSQL URL format: postgresql://username:password@hostname:port/database
    uri = URI.parse(url)

    # Extract userinfo (username:password)
    [username, password] = String.split(uri.userinfo, ":")

    # Extract hostname and port
    port = uri.port || 5432

    # Extract database name (remove leading slash)
    database = String.replace_prefix(uri.path, "/", "")

    %{
      username: username,
      password: password,
      hostname: uri.host,
      port: port,
      database: database
    }
  end

  defp verify_hostname(hostname) do
    Logger.info("Verifying hostname: #{hostname}...")

    case :inet.gethostbyname(String.to_charlist(hostname)) do
      {:ok, _} ->
        Logger.info("Hostname #{hostname} resolved successfully.")
      {:error, reason} ->
        Logger.error("Could not resolve hostname #{hostname}: #{inspect(reason)}")
        Logger.info("Possible solutions:")
        Logger.info("1. Check your internet connection")
        Logger.info("2. Verify the SUPABASE_DATABASE_URL in your .env file")
        Logger.info("3. Add the hostname to your /etc/hosts file")
        Logger.info("4. Try using the IP address directly instead of the hostname")
        Logger.info("5. Ensure you have proper VPN access if the database is behind a firewall")
        exit({:shutdown, 1})
    end
  end

  defp download_production_db(db_config, dump_file) do
    # Build pg_dump command - only dump the public schema and skip Supabase system schemas
    pg_dump_cmd = [
      "pg_dump",
      "--host=#{db_config.hostname}",
      "--port=#{db_config.port}",
      "--username=#{db_config.username}",
      "--format=c",  # Use custom format for better compression and flexibility
      "--file=#{dump_file}",
      "--schema=public",  # Only include the public schema
      "--no-owner",  # Don't include ownership commands
      "--no-privileges",  # Don't include privilege commands
      "--no-comments",  # Exclude comments for simplicity
      "--disable-triggers",  # Handle circular foreign key dependencies
      db_config.database
    ]

    # Set PGPASSWORD environment variable for authentication
    env = [{"PGPASSWORD", db_config.password}]

    # Execute pg_dump command
    case System.cmd(List.first(pg_dump_cmd), Enum.slice(pg_dump_cmd, 1..-1//1), env: env) do
      {_, 0} ->
        Logger.info("Production database dump created successfully")
      {error, code} ->
        Logger.error("Failed to dump production database. Error code: #{code}, Output: #{error}")
        exit({:shutdown, 1})
    end
  end

  defp import_database(dump_file) do
    # Get local database configuration from config/dev.exs
    app_name = :trivia_advisor
    repo_config = Application.get_env(app_name, TriviaAdvisor.Repo)

    # Build pg_restore command for local database
    pg_restore_cmd = [
      "pg_restore",
      "--host=#{repo_config[:hostname]}",
      "--port=#{repo_config[:port] || 5432}",
      "--username=#{repo_config[:username]}",
      "--dbname=#{repo_config[:database]}",
      "--schema=public",  # Only restore the public schema
      "--clean",  # Clean (drop) database objects before recreating
      "--if-exists",  # Add if-exists flag to avoid errors on missing elements
      "--no-owner",  # Do not set ownership of objects to match the original database
      "--no-acl",  # Don't include access privilege (grant/revoke) commands
      "--no-comments",  # Exclude comments for simplicity
      "--disable-triggers",  # Handle circular foreign key dependencies
      "--single-transaction",  # All or nothing transaction
      dump_file
    ]

    # Set PGPASSWORD environment variable for authentication
    env = [{"PGPASSWORD", repo_config[:password]}]

    # Execute pg_restore command
    case System.cmd(List.first(pg_restore_cmd), Enum.slice(pg_restore_cmd, 1..-1//1), env: env) do
      {_, 0} ->
        Logger.info("Production database imported successfully")
      {error, code} ->
        Logger.error("Failed to import production database. Error code: #{code}, Output: #{error}")
        exit({:shutdown, 1})
    end
  end

  defp sync_files_from_tigris(access_key_id, secret_access_key, bucket_name) do
    # Ensure required applications are started
    ensure_applications_started()

    # Step 1: Remove existing local files
    Logger.info("Removing existing local files...")
    remove_existing_uploads()

    # Configure ExAws with Tigris credentials
    configure_aws_for_tigris(access_key_id, secret_access_key)

    # Step 2: Download files from Tigris
    Logger.info("Downloading files from Tigris bucket: #{bucket_name}...")

    # First - explicitly handle the venues directory which seems to be missing
    Logger.info("EXPLICITLY checking for venues directory...")
    download_venues(bucket_name)

    # Then download the rest
    download_files_from_bucket(bucket_name)
  end

  defp ensure_applications_started do
    # Start required applications for ExAws
    [:hackney, :telemetry, :ex_aws]
    |> Enum.each(fn app ->
      case Application.ensure_all_started(app) do
        {:ok, _} -> :ok
        {:error, {reason, app}} ->
          Logger.warning("Failed to start #{app} application: #{reason}")
      end
    end)
  end

  defp configure_aws_for_tigris(access_key_id, secret_access_key) do
    # Configure ExAws to use Tigris credentials and endpoint
    Application.put_env(:ex_aws, :access_key_id, access_key_id)
    Application.put_env(:ex_aws, :secret_access_key, secret_access_key)

    # Configure S3 endpoint for Tigris
    Application.put_env(:ex_aws, :s3,
      %{
        host: "fly.storage.tigris.dev",
        scheme: "https://",
        region: "auto"
      }
    )
  end

  defp remove_existing_uploads do
    case File.rm_rf(@uploads_dir) do
      {:ok, _} ->
        Logger.info("Successfully removed #{@uploads_dir} directory")
      {:error, reason, file} ->
        Logger.warning("Error removing #{file}: #{inspect(reason)}")
    end

    # Create fresh directory structure
    File.mkdir_p!(@uploads_dir)
  end

  defp download_files_from_bucket(bucket) do
    Logger.info("Downloading files from bucket: #{bucket}")

    # Create the uploads directory
    File.mkdir_p!(@uploads_dir)

    # Define the directories we specifically want to check and download
    directories_to_check = [
      "",
      "uploads/google_place_images/",
      "uploads/venues/",
      "uploads/venue_images/",
      "uploads/performers/",
      "uploads/performer_images/"
    ]

    Logger.info("Starting to download all files from bucket: #{bucket}")
    # Check each directory explicitly
    Enum.each(directories_to_check, fn prefix ->
      Logger.info("Checking directory: #{prefix}")
      download_directory(bucket, prefix)
    end)
  end

  defp download_directory(bucket, prefix) do
    download_objects_with_continuation(bucket, prefix, nil)
  end

  defp download_objects_with_continuation(bucket, prefix, continuation_token) do
    # Build options for list_objects_v2
    options = if is_nil(continuation_token) do
      [prefix: prefix]
    else
      [prefix: prefix, continuation_token: continuation_token]
    end

    # Use list_objects_v2 which supports pagination and is more reliable
    case ExAws.S3.list_objects_v2(bucket, options) |> ExAws.request() do
      {:ok, %{body: %{contents: objects, is_truncated: is_truncated, next_continuation_token: next_token}}}
          when is_list(objects) and objects != [] ->
        Logger.info("Found #{length(objects)} objects in #{prefix} (truncated: #{is_truncated})")

        # Download these objects
        objects
        |> Enum.each(fn %{key: key} ->
          download_object(bucket, key)
        end)

        # If the response was truncated, continue with the next batch
        if is_truncated do
          download_objects_with_continuation(bucket, prefix, next_token)
        end

      {:ok, %{body: %{contents: []}}} ->
        Logger.info("No objects found in directory #{prefix}")

      {:error, error} ->
        Logger.error("Failed to list objects in #{prefix}: #{inspect(error)}")
    end
  end

  defp download_object(bucket, key) do
    # We want to preserve the exact folder structure, but skip the "uploads/" prefix
    # from the Tigris bucket if it exists
    local_path = if String.starts_with?(key, "uploads/") do
      # Remove the leading "uploads/" as we're already putting files in the uploads dir
      clean_key = String.replace_prefix(key, "uploads/", "")
      Path.join(@uploads_dir, clean_key)
    else
      # Just use the key as-is if it doesn't have the uploads prefix
      Path.join(@uploads_dir, key)
    end

    # Create all parent directories as needed
    File.mkdir_p!(Path.dirname(local_path))

    Logger.info("Downloading #{bucket}/#{key} to #{local_path}")

    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        # Write file content
        File.write!(local_path, body)
        Logger.info("Successfully downloaded #{local_path}")

      {:error, error} ->
        Logger.error("Failed to download #{bucket}/#{key}: #{inspect(error)}")
    end
  end

  defp download_venues(bucket) do
    venue_prefix = "uploads/venues/"
    Logger.info("Directly downloading all objects with prefix: #{venue_prefix}")

    case ExAws.S3.list_objects_v2(bucket, prefix: venue_prefix) |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} when is_list(objects) and objects != [] ->
        Logger.info("FOUND #{length(objects)} objects in venues directory!")

        # Create venues directory structure
        venues_dir = Path.join(@uploads_dir, "venues")
        File.mkdir_p!(venues_dir)

        # Download each object
        objects
        |> Enum.each(fn %{key: key} ->
          download_object(bucket, key)
        end)

      {:ok, %{body: %{contents: []}}} ->
        Logger.info("No objects found in venues directory")

      {:error, error} ->
        Logger.error("Error listing objects in venues directory: #{inspect(error)}")
    end
  end
end

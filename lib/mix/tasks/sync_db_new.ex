defmodule Mix.Tasks.SyncDbNew do
  @moduledoc """
  Syncs the local development database with the production database from Supabase.

  This task:
  1. Resets the local database using `mix ecto.reset`
  2. Downloads the production database from Supabase using the SUPABASE_DATABASE_URL from .env
  3. Imports the downloaded database into the local environment

  ## Examples

      mix sync_db_new

  """
  use Mix.Task
  require Logger

  @shortdoc "Syncs local database with production Supabase database"

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

      # Step 4: Re-run migrations after import to apply our new schema changes
      Logger.info("Re-applying local migrations after production import...")
      Mix.Task.rerun("ecto.migrate", [])

      # Step 5: Create the duplicate view after migrations are complete
      Logger.info("Creating duplicate detection view...")
      Mix.Task.rerun("create_duplicate_view", [])

      Logger.info("Database sync completed successfully!")
    rescue
      e ->
        Logger.error("Error syncing database: #{inspect(e)}")
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
end

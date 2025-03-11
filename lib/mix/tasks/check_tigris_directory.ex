defmodule Mix.Tasks.CheckTigrisDirectory do
  @moduledoc """
  Checks if a specific directory exists in the Tigris bucket.

  This task will check if a directory exists and list its contents.

  ## Examples

      mix check_tigris_directory uploads/venues/
  """
  use Mix.Task
  require Logger

  @shortdoc "Checks if a directory exists in the Tigris bucket"

  @impl Mix.Task
  def run(args) do
    # Get the directory to check
    dir_to_check = if length(args) > 0, do: List.first(args), else: "uploads/venues/"

    # Load environment variables from .env file
    load_env_vars()

    # Get Tigris credentials from environment variables
    tigris_access_key_id = System.get_env("TIGRIS_ACCESS_KEY_ID")
    tigris_secret_access_key = System.get_env("TIGRIS_SECRET_ACCESS_KEY")
    tigris_bucket_name = System.get_env("TIGRIS_BUCKET_NAME") || "trivia-app"

    if is_nil(tigris_access_key_id) || is_nil(tigris_secret_access_key) do
      Logger.error("Tigris credentials not found in .env file. Make sure TIGRIS_ACCESS_KEY_ID and TIGRIS_SECRET_ACCESS_KEY are set.")
      exit({:shutdown, 1})
    end

    # Ensure required applications are started
    ensure_applications_started()

    # Configure ExAws with Tigris credentials
    configure_aws_for_tigris(tigris_access_key_id, tigris_secret_access_key)

    # Check if the directory exists
    Logger.info("Checking if directory exists: #{dir_to_check} in bucket: #{tigris_bucket_name}...")
    check_directory(tigris_bucket_name, dir_to_check)
  end

  defp load_env_vars do
    case Code.ensure_loaded(DotenvParser) do
      {:module, _} ->
        DotenvParser.load_file(".env")
      _ ->
        Logger.warning("DotenvParser module not found. Assuming environment variables are already loaded.")
    end
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

  defp check_directory(bucket, prefix) do
    case ExAws.S3.list_objects_v2(bucket, prefix: prefix) |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} when is_list(objects) and objects != [] ->
        Logger.info("Directory exists! Found #{length(objects)} objects in #{prefix}")

        # Print the first few objects
        Enum.take(objects, 10)
        |> Enum.each(fn %{key: key} ->
          Logger.info("  - #{key}")
        end)

      {:ok, %{body: %{contents: []}}} ->
        Logger.info("Directory exists but is empty: #{prefix}")

      {:error, error} ->
        Logger.error("Error checking directory: #{inspect(error)}")
    end
  end
end

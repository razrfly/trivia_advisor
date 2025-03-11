defmodule Mix.Tasks.ListTigrisObjects do
  @moduledoc """
  Lists all objects in the Tigris bucket without downloading them.

  This task will print all keys from the specified Tigris bucket to help
  diagnose directory structure issues.

  ## Examples

      mix list_tigris_objects
  """
  use Mix.Task
  require Logger

  @shortdoc "Lists all objects in the Tigris bucket"

  @impl Mix.Task
  def run(_args) do
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

    # List objects in the bucket
    Logger.info("Listing objects in Tigris bucket: #{tigris_bucket_name}...")
    list_bucket_objects(tigris_bucket_name)
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

  defp list_bucket_objects(bucket) do
    # List all objects in the bucket
    case ExAws.S3.list_objects(bucket) |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} when is_list(objects) and objects != [] ->
        Logger.info("Found #{length(objects)} objects in bucket #{bucket}")

        # Group keys by directory structure
        grouped_keys = objects
        |> Enum.map(fn %{key: key} -> key end)
        |> Enum.sort()
        |> group_by_directory_prefix()

        # Print sorted keys by directory
        print_grouped_keys(grouped_keys)

        # Save all keys to a file
        all_keys = objects |> Enum.map(fn %{key: key} -> key end) |> Enum.sort()
        File.write!("tigris_keys.txt", Enum.join(all_keys, "\n"))
        Logger.info("Saved all #{length(all_keys)} keys to tigris_keys.txt")

      {:ok, %{body: %{contents: []}}} ->
        Logger.info("No objects found in bucket #{bucket}")

      {:ok, %{body: body}} ->
        Logger.info("Unexpected response format: #{inspect(body)}")

      {:error, {:http_error, 404, _}} ->
        Logger.error("Bucket #{bucket} not found. Please check your TIGRIS_BUCKET_NAME.")
        exit({:shutdown, 1})

      {:error, error} ->
        Logger.error("Failed to list objects in bucket #{bucket}: #{inspect(error)}")
        exit({:shutdown, 1})
    end
  end

  defp group_by_directory_prefix(keys) do
    keys
    |> Enum.reduce(%{}, fn key, acc ->
      # Extract the top-level directory from the key
      directory = case String.split(key, "/", parts: 2) do
        [dir, _] -> dir
        [single] -> "root"
      end

      # Update the accumulator with the new key under its directory
      Map.update(acc, directory, [key], fn existing -> [key | existing] end)
    end)
  end

  defp print_grouped_keys(grouped_keys) do
    Logger.info("===== Grouped Keys by Directory =====")

    grouped_keys
    |> Enum.each(fn {directory, keys} ->
      Logger.info("Directory: #{directory} (#{length(keys)} files)")

      # Print first 10 keys as examples
      keys
      |> Enum.take(10)
      |> Enum.each(fn key -> Logger.info("  - #{key}") end)

      # Indicate if there are more keys
      if length(keys) > 10 do
        Logger.info("  ... and #{length(keys) - 10} more files")
      end
    end)
  end
end

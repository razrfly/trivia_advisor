defmodule Mix.Tasks.Sitemap.TestS3 do
  @moduledoc """
  Tests S3 connectivity for the sitemap generation.

  ## Usage

      mix sitemap.test_s3
  """
  use Mix.Task
  require Logger

  @shortdoc "Tests S3 connectivity for the sitemap generation"

  @impl Mix.Task
  def run(_args) do
    # Start required apps
    [:logger, :ecto, :ex_aws, :hackney]
    |> Enum.each(&Application.ensure_all_started/1)

    # Start the repo
    TriviaAdvisor.Repo.start_link()

    # Set production environment to test S3 connectivity
    Application.put_env(:trivia_advisor, :environment, :prod)

    # Test S3 connectivity
    Logger.info("Testing S3 connectivity...")
    TriviaAdvisor.Sitemap.test_s3_connectivity()
  end
end

defmodule Mix.Tasks.Sitemap.Generate.S3 do
  @moduledoc """
  Generates a sitemap and forces storage to S3 regardless of environment.

  ## Usage

      mix sitemap.generate.s3
  """
  use Mix.Task
  require Logger

  @shortdoc "Generates a sitemap and stores it on S3"

  @impl Mix.Task
  def run(_args) do
    # Start required apps
    [:logger, :ecto, :ex_aws, :hackney]
    |> Enum.each(&Application.ensure_all_started/1)

    # Start your application (this loads all configs)
    Application.ensure_all_started(:trivia_advisor)

    # Force production environment mode to use S3 storage
    Application.put_env(:trivia_advisor, :environment, :prod)

    # Force quizadvisor.com as the host for sitemaps
    config = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)

    # Update the host to quizadvisor.com
    updated_url_config = put_in(config[:url][:host], "quizadvisor.com")
    Application.put_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint, updated_url_config)

    # Output the base URL that will be used
    host = "quizadvisor.com"
    Logger.info("Using host: #{host} for sitemap URLs")

    # Generate the sitemap
    Logger.info("Generating sitemap with S3 storage...")
    case TriviaAdvisor.Sitemap.generate_and_persist() do
      :ok ->
        Logger.info("Sitemap generation and S3 upload completed successfully.")

        # Test connectivity to validate the upload worked
        Logger.info("Verifying S3 upload...")
        TriviaAdvisor.Sitemap.test_s3_connectivity()

      {:error, error} ->
        Logger.error("Sitemap generation failed: #{inspect(error, pretty: true)}")
    end
  end
end

defmodule Mix.Tasks.Sitemap.DiagnoseS3 do
  @moduledoc """
  Performs comprehensive diagnostics on S3 connectivity and permissions.
  Useful for debugging sitemap generation issues with S3 storage.

  ## Usage

      mix sitemap.diagnose_s3
  """
  use Mix.Task
  require Logger
  alias TriviaAdvisor.Sitemap

  @shortdoc "Diagnoses S3 connectivity and permissions for sitemap storage"

  @impl Mix.Task
  def run(_args) do
    # Start required apps
    [:logger, :ecto, :ex_aws, :hackney]
    |> Enum.each(&Application.ensure_all_started/1)

    # Start your application (this loads all configs)
    Application.ensure_all_started(:trivia_advisor)

    # Force production environment mode to use S3 storage
    Application.put_env(:trivia_advisor, :environment, :prod)

    # Check environment variables for AWS/Tigris credentials
    IO.puts("\n=== ENVIRONMENT VARIABLES ===")
    check_env_var("TIGRIS_ACCESS_KEY_ID")
    check_env_var("TIGRIS_SECRET_ACCESS_KEY")
    check_env_var("TIGRIS_BUCKET_NAME")
    check_env_var("AWS_ACCESS_KEY_ID")
    check_env_var("AWS_SECRET_ACCESS_KEY")
    check_env_var("BUCKET_NAME")
    check_env_var("AWS_REGION")

    # Test basic S3 connectivity
    IO.puts("\n=== S3 CONNECTIVITY TEST ===")
    case Sitemap.test_s3_connectivity() do
      {:ok, response} ->
        IO.puts("✅ S3 connectivity test successful!")

        # Get the bucket name from the response
        bucket = response.body[:name] || "unknown bucket"

        # Test writing a small file
        IO.puts("\n=== S3 WRITE TEST ===")
        test_file = "sitemap-test-#{:os.system_time(:millisecond)}.txt"
        test_content = "This is a test file to verify S3 write access. Created at #{DateTime.utc_now()}."

        IO.puts("Writing test file: #{test_file}")

        case ExAws.S3.put_object(bucket, test_file, test_content)
             |> ExAws.request() do
          {:ok, _} ->
            IO.puts("✅ S3 write test successful!")

            # Test reading the file back
            IO.puts("\n=== S3 READ TEST ===")
            case ExAws.S3.get_object(bucket, test_file) |> ExAws.request() do
              {:ok, response} ->
                if response.body == test_content do
                  IO.puts("✅ S3 read test successful!")
                else
                  IO.puts("❌ S3 read test failed - content mismatch")
                  IO.puts("Expected: #{test_content}")
                  IO.puts("Got: #{response.body}")
                end

              {:error, error} ->
                IO.puts("❌ S3 read test failed: #{inspect(error, pretty: true)}")
            end

            # Clean up the test file
            IO.puts("\n=== S3 DELETE TEST ===")
            case ExAws.S3.delete_object(bucket, test_file) |> ExAws.request() do
              {:ok, _} -> IO.puts("✅ S3 delete test successful!")
              {:error, error} -> IO.puts("❌ S3 delete test failed: #{inspect(error, pretty: true)}")
            end

          {:error, error} ->
            IO.puts("❌ S3 write test failed: #{inspect(error, pretty: true)}")
        end

      {:error, error} ->
        IO.puts("❌ S3 connectivity test failed: #{inspect(error, pretty: true)}")
    end

    # Final summary
    IO.puts("\n=== DIAGNOSIS COMPLETE ===")
    IO.puts("If all tests passed, sitemap generation with S3 storage should work correctly.")
    IO.puts("If any tests failed, check your S3 credentials and permissions.")
  end

  # Helper to check environment variables
  defp check_env_var(name) do
    case System.get_env(name) do
      nil -> IO.puts("❌ #{name}: Not set")
      value when byte_size(value) > 0 ->
        masked = if String.contains?(name, "SECRET") || String.contains?(name, "KEY") do
          "#{String.slice(value, 0..5)}..." |> String.pad_trailing(10, "*")
        else
          value
        end
        IO.puts("✅ #{name}: #{masked}")
      _ -> IO.puts("❓ #{name}: Empty string")
    end
  end
end

defmodule Mix.Tasks.Sitemap.Generate do
  use Mix.Task
  require Logger

  @shortdoc "Generates XML sitemap for the TriviaAdvisor website"

  @moduledoc """
  Generates an XML sitemap for the TriviaAdvisor website.

  This task uses the Sitemapper library to generate a sitemap
  for all cities and venues in the database.

  The sitemap will be stored based on the environment:
  - In development: stored in the local filesystem
  - In production: stored in an S3 bucket

  ## Options

  * `--s3` - Force S3 storage even in development environment

  ## Examples

      # Generate sitemap using default storage (local in dev, S3 in prod)
      $ mix sitemap.generate

      # Force S3 storage even in development
      $ mix sitemap.generate --s3
  """

  @impl Mix.Task
  def run(args) do
    # Parse args
    {opts, _, _} = OptionParser.parse(args, strict: [s3: :boolean])
    use_s3 = Keyword.get(opts, :s3, false)

    # Determine which apps to start based on storage type
    apps_to_start = [:logger, :ecto_sql, :postgrex]

    # If using S3, ensure the required dependencies are started
    if use_s3 do
      # Also start S3-specific applications
      [:ex_aws, :hackney] |> Enum.each(&Application.ensure_all_started/1)
    end

    # Start all required apps
    Enum.each(apps_to_start, &Application.ensure_all_started/1)

    # Start your application to make sure the database and other services are ready
    {:ok, _} = Application.ensure_all_started(:trivia_advisor)

    # Force production environment if s3 flag is used
    if use_s3 do
      Logger.info("Using S3 storage as requested via --s3 flag")
      Application.put_env(:trivia_advisor, :environment, :prod)

      # Force quizadvisor.com as the host for sitemaps when using S3 storage
      config = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)

      # Update the host to quizadvisor.com
      updated_url_config = put_in(config[:url][:host], "quizadvisor.com")
      Application.put_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint, updated_url_config)

      # Output the base URL that will be used
      host = "quizadvisor.com"
      Logger.info("Using host: #{host} for sitemap URLs")
    end

    Logger.info("Starting sitemap generation task")

    # Generate and persist the sitemap
    case TriviaAdvisor.Sitemap.generate_and_persist() do
      :ok ->
        Logger.info("Sitemap generation task completed successfully")

        # If using S3, verify the upload
        if use_s3 do
          Logger.info("Verifying S3 upload...")
          TriviaAdvisor.Sitemap.test_s3_connectivity()
        end

        :ok

      {:error, error} ->
        Logger.error("Sitemap generation task failed: #{inspect(error, pretty: true)}")
        exit({:shutdown, 1})
    end
  end
end

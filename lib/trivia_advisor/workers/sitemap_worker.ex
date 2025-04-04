defmodule TriviaAdvisor.Workers.SitemapWorker do
  @moduledoc """
  Worker that generates and persists a sitemap.
  This is scheduled to run daily through Oban.
  """
  use Oban.Worker, queue: :default, max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Log worker details
    Logger.info("Starting scheduled sitemap generation")

    # Log environment details
    env = Application.get_env(:trivia_advisor, :environment)
    Logger.info("Running sitemap generation in #{env || "undefined"} environment")

    # Check AWS/Tigris credentials availability
    tigris_key = System.get_env("TIGRIS_ACCESS_KEY_ID")
    tigris_secret = System.get_env("TIGRIS_SECRET_ACCESS_KEY")
    aws_key = System.get_env("AWS_ACCESS_KEY_ID")
    aws_secret = System.get_env("AWS_SECRET_ACCESS_KEY")

    Logger.info("Credentials available: Tigris (#{!is_nil(tigris_key) && !is_nil(tigris_secret)}), AWS (#{!is_nil(aws_key) && !is_nil(aws_secret)})")

    # Ensure we're in production mode for sitemap generation
    Application.put_env(:trivia_advisor, :environment, :prod)

    # Force quizadvisor.com as the host for sitemaps in production
    config = Application.get_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint)

    # Update the host to quizadvisor.com to ensure correct URLs in the sitemap
    updated_url_config = put_in(config[:url][:host], "quizadvisor.com")
    Application.put_env(:trivia_advisor, TriviaAdvisorWeb.Endpoint, updated_url_config)

    Logger.info("Using host: quizadvisor.com for sitemap URLs")

    # Generate and persist sitemap
    case TriviaAdvisor.Sitemap.generate_and_persist() do
      :ok ->
        Logger.info("Scheduled sitemap generation completed successfully")
        :ok
      {:error, error} ->
        Logger.error("Scheduled sitemap generation failed: #{inspect(error, pretty: true)}")
        # We still return :ok to avoid retries, since we've already logged the error
        :ok
    end
  end
end

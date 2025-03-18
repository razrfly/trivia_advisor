defmodule TriviaAdvisor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Add Sentry logger handler to capture crashed process exceptions
    if Application.get_env(:trivia_advisor, :env) == :prod do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })
    end

    children = [
      TriviaAdvisorWeb.Telemetry,
      TriviaAdvisor.Repo,
      {DNSCluster, query: Application.get_env(:trivia_advisor, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:trivia_advisor, Oban)},
      {Phoenix.PubSub, name: TriviaAdvisor.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: TriviaAdvisor.Finch},
      # Start the Unsplash service for image caching
      TriviaAdvisor.Services.UnsplashService,
      # Start Google Places service for venue image fetching
      {TriviaAdvisor.Services.GooglePlacesService, []},
      # Start the Google Place Image Store service
      {TriviaAdvisor.Services.GooglePlaceImageStore, []},
      # Start to serve requests, typically the last entry
      TriviaAdvisorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TriviaAdvisor.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Schedule the daily image refresh job after the application starts
    if Application.get_env(:trivia_advisor, :env) != :test do
      schedule_image_refresh_jobs()
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TriviaAdvisorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Schedule the image refresh jobs
  defp schedule_image_refresh_jobs do
    # Schedule with a slight delay to ensure Oban is fully started
    Task.async(fn ->
      # Wait a bit to make sure everything is up and running
      Process.sleep(5000)
      # Only run an initial refresh to ensure we have images
      # (daily scheduling is now handled by Oban.Plugins.Cron)
      TriviaAdvisor.Workers.UnsplashImageRefresher.schedule_country_refresh()
    end)
  end
end

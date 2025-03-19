defmodule TriviaAdvisorWeb.Router do
  use TriviaAdvisorWeb, :router

  import Oban.Web.Router
  import Plug.BasicAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TriviaAdvisorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TriviaAdvisorWeb.Plugs.CloudflareRealIp
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Basic authentication for Oban Web
  pipeline :oban_auth do
    plug :basic_auth, username: "admin", password: "trivia"
  end

  scope "/", TriviaAdvisorWeb do
    pipe_through :browser

    live "/", HomeLive.Index, :index
    live "/cities/:slug", CityLive.Show, :show
    live "/cities", CityLive.Index, :index
    live "/countries/:slug", CountryLive.Show, :show
    live "/venues/:slug", VenueLive.Show, :show

    # Admin route for image cache management (only in dev)
    if Mix.env() == :dev do
      live "/dev/cache", DevLive.Cache, :index
    end
  end

  # Oban Web UI routes for version 2.11
  scope "/admin" do
    pipe_through [:browser, :oban_auth]

    oban_dashboard "/oban"
  end

  # Other scopes may use custom stacks.
  # scope "/api", TriviaAdvisorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:trivia_advisor, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TriviaAdvisorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

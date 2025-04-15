# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :trivia_advisor, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [
    default: 20,
    google_api: [limit: 5],
    scraper: [limit: 10],
    images: [limit: 2]
  ],
  repo: TriviaAdvisor.Repo,
  plugins: [
    # Use dynamic plugin list with Cron only in production
    {Oban.Plugins.Pruner, max_age: 604800}  # 7 days in seconds
  ]

# We'll add the Cron plugin conditionally in the environments

# Add Oban Web UI configuration
config :oban_web,
  repo: TriviaAdvisor.Repo,
  prefix: "public"

config :trivia_advisor,
  ecto_repos: [TriviaAdvisor.Repo],
  generators: [timestamp_type: :utc_datetime],
  google_api_key: System.get_env("GOOGLE_API_KEY")


# Add configuration for venue proximity validation
config :trivia_advisor, :venue_validation,
  min_duplicate_distance: 50,
  duplicate_check_enabled: true

# Configures the endpoint
config :trivia_advisor, TriviaAdvisorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TriviaAdvisorWeb.ErrorHTML, json: TriviaAdvisorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TriviaAdvisor.PubSub,
  live_view: [signing_salt: "4q0B5zbP"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :trivia_advisor, TriviaAdvisor.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  trivia_advisor: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  trivia_advisor: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Waffle configuration
config :waffle,
  storage: Waffle.Storage.Local,
  storage_dir_prefix: "priv/static",
  asset_host: {:system, "ASSET_HOST"},
  base_url: "/uploads"

# Make sure Waffle knows about our repo
config :waffle,
  ecto_repos: [TriviaAdvisor.Repo]

# Add ImageMagick config for Mogrify
config :mogrify,
  convert_path: "convert",
  identify_path: "identify"

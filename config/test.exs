import Config
config :trivia_advisor, Oban, testing: :manual

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :trivia_advisor, TriviaAdvisor.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "trivia_advisor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :trivia_advisor, TriviaAdvisorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "IUSEY9vL4x7XG+RTor9OkPpBMiC44+gXRzwD+W8iSFVquceze2Mz9XXOP1yeubxI",
  server: false

# In test we don't send emails
config :trivia_advisor, TriviaAdvisor.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger,
  # Allow info logs for testing Oban jobs
  level: :info,
  handle_otp_reports: false,
  handle_sasl_reports: false

# Add this to silence Ecto SQL logs during tests
config :logger, Ecto.LogEntry, level: :error

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :wallaby,
  driver: Wallaby.Chrome,
  chrome: [
    headless: true
  ]

config :trivia_advisor, :google_lookup, TriviaAdvisor.Scraping.MockGoogleLookup

config :trivia_advisor,
  google_api_key: "test_api_key"

# Add HTTPoison mock
config :trivia_advisor, :http_client, HTTPoison.Mock

# Set environment tag
config :trivia_advisor, env: :test

config :trivia_advisor, Oban,
  testing: :inline,
  queues: false,
  plugins: false

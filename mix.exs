defmodule TriviaAdvisor.MixProject do
  use Mix.Project

  def project do
    [
      app: :trivia_advisor,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TriviaAdvisor.Application, []},
      extra_applications: [:logger, :runtime_tools, :waffle]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.21"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.5"},
      {:floki, "~> 0.37.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:slugify, "~> 1.3"},
      {:httpoison, "~> 2.0"},
      {:wallaby, "~> 0.30.0", runtime: false},
      {:html_entities, "~> 0.5"},
      {:dotenv_parser, "~> 2.0"},
      {:bypass, "~> 2.1", only: :test},
      {:countries, "~> 1.6"},
      {:mox, "~> 1.0", only: :test},
      {:money, "~> 1.12"},
      {:decimal, "~> 2.0"},
      {:waffle, "~> 1.1.7"},
      {:waffle_ecto, "~> 0.0.12"},
      {:ex_aws, "~> 2.5.10"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      {:mogrify, "~> 0.9.3"},
      {:mime, "~> 2.0"},
      {:timex, "~> 3.7"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11"},
      {:plug, "~> 1.16"},
      {:igniter, "~> 0.6.7", only: [:dev]},
      {:sentry, "~> 11.0"},
      {:hackney, "~> 1.8"},
      {:ex_cldr, "~> 2.42.0"},
      {:ex_cldr_dates_times, "~> 2.22.0"},
      {:ex_cldr_calendars, "~> 2.1.0"},
      {:sitemapper, "~> 0.9"},
      {:mock, "~> 0.3.7", only: :test},
      {:json_ld, "~> 0.3"},
      {:ecto_soft_delete, "~> 2.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind trivia_advisor", "esbuild trivia_advisor"],
      "assets.deploy": [
        "tailwind trivia_advisor --minify",
        "esbuild trivia_advisor --minify",
        "phx.digest"
      ]
    ]
  end
end

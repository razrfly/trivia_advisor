defmodule TriviaAdvisor.Repo do
  use Ecto.Repo,
    otp_app: :trivia_advisor,
    adapter: Ecto.Adapters.Postgres
end

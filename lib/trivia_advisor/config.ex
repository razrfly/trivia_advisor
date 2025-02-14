defmodule TriviaAdvisor.Config do
  @moduledoc """
  Handles application configuration.
  """

  def google_api_key do
    Application.get_env(:trivia_advisor, :google_api_key) ||
      raise "Google API key not configured. Set GOOGLE_API_KEY environment variable."
  end
end

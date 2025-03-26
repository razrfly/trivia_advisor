defmodule TriviaAdvisor.ObanCase do
  @moduledoc """
  This module defines the setup for tests requiring
  Oban job testing functionality.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import ExUnit.CaptureLog
      import TriviaAdvisor.ObanCase
    end
  end

  @doc """
  Helper to perform an Oban job and return the result
  """
  def perform_job(worker_module, args, opts \\ []) do
    # Use the Oban.Testing API directly with the correct signature
    Oban.Testing.perform_job(worker_module, args, opts)
  end
end

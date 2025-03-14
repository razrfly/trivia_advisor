# Test script for GeeksWhoDrinkIndexJob with error catching
# Run with: mix run lib/debug/test_geeks_who_drink.exs

defmodule DebugGeeksWhoDrink do
  require Logger

  def run do
    # Initialize services needed by the job if not already started
    start_or_ignore_service(TriviaAdvisor.Services.GooglePlacesService)
    start_or_ignore_service(TriviaAdvisor.Services.GooglePlaceImageStore)

    try do
      # Create a fake job with a limit of 3 venues
      job = %Oban.Job{args: %{"limit" => 3}}

      # Run the job directly and capture the result
      result = TriviaAdvisor.Scraping.Oban.GeeksWhoDrinkIndexJob.perform(job)
      Logger.info("Job completed with result: #{inspect(result)}")
    rescue
      e ->
        Logger.error("Error executing job: #{Exception.message(e)}")
        Logger.error("Stack trace:\n#{Exception.format_stacktrace(__STACKTRACE__)}")
    catch
      kind, value ->
        Logger.error("Caught #{kind}: #{inspect(value)}")
        Logger.error("Stack trace:\n#{Exception.format_stacktrace(__STACKTRACE__)}")
    end
  end

  defp start_or_ignore_service(module) do
    case module.start_link([]) do
      {:ok, _pid} -> Logger.info("Started #{module}")
      {:error, {:already_started, _pid}} -> Logger.info("Service #{module} already running")
      error -> Logger.error("Failed to start #{module}: #{inspect(error)}")
    end
  end
end

# Run the debug function
DebugGeeksWhoDrink.run()

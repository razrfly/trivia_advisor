# Script to run the Unsplash image refresher for all countries or cities
# Run with: mix run lib/debug/refresh_images.exs [country|city|all] [batch_size] [delay_seconds]
#
# Examples:
# - Refresh all countries: mix run lib/debug/refresh_images.exs country
# - Refresh all cities with batch size 5: mix run lib/debug/refresh_images.exs city 5
# - Refresh both countries and cities with 3-second delay: mix run lib/debug/refresh_images.exs all 10 3

alias TriviaAdvisor.Workers.UnsplashImageRefresher
require Logger

# Default values
default_batch_size = 10
default_delay_seconds = 2

# Parse command line arguments
args = System.argv()
type = List.first(args) || "all"
batch_size =
  if length(args) >= 2 do
    {size, _} = Integer.parse(Enum.at(args, 1))
    size
  else
    default_batch_size
  end
delay_seconds =
  if length(args) >= 3 do
    {delay, _} = Integer.parse(Enum.at(args, 2))
    delay
  else
    default_delay_seconds
  end

# Update the request delay in the worker
:persistent_term.put(:unsplash_request_delay, delay_seconds * 1000)

IO.puts("Running image refresh with:")
IO.puts("- Type: #{type}")
IO.puts("- Batch size: #{batch_size}")
IO.puts("- Delay between requests: #{delay_seconds} seconds")

case type do
  "country" ->
    IO.puts("\nScheduling refresh for all countries...")
    countries = TriviaAdvisor.Repo.all(from c in TriviaAdvisor.Locations.Country, select: c.name)
    IO.puts("Found #{length(countries)} countries to refresh")

    # Process countries in batches
    countries
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      # Insert job to run immediately (no schedule_in)
      {:ok, job} = %{type: "country", names: batch}
                  |> UnsplashImageRefresher.new()
                  |> Oban.insert()

      IO.puts("Scheduled batch #{index + 1} with #{length(batch)} countries - Job ID: #{job.id}")
    end)

  "city" ->
    IO.puts("\nScheduling refresh for all cities...")
    cities = TriviaAdvisor.Repo.all(from c in TriviaAdvisor.Locations.City, select: c.name)
    IO.puts("Found #{length(cities)} cities to refresh")

    # Process cities in batches
    cities
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      # Insert job to run immediately (no schedule_in)
      {:ok, job} = %{type: "city", names: batch}
                  |> UnsplashImageRefresher.new()
                  |> Oban.insert()

      IO.puts("Scheduled batch #{index + 1} with #{length(batch)} cities - Job ID: #{job.id}")
    end)

  "all" ->
    IO.puts("\nScheduling refresh for all countries and cities...")
    # Call the worker's functions which handle batching
    UnsplashImageRefresher.schedule_country_refresh()
    UnsplashImageRefresher.schedule_city_refresh()

  _ ->
    IO.puts("\nInvalid type '#{type}'. Use 'country', 'city', or 'all'.")
end

IO.puts("\nJob(s) scheduled! Check your logs or the Oban dashboard at http://localhost:4000/oban")
IO.puts("The worker will process images with a #{delay_seconds}-second delay between requests.")

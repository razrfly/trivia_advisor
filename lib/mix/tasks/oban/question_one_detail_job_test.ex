defmodule Mix.Tasks.Oban.QuestionOneDetailJobTest do
  use Mix.Task

  @shortdoc "Tests the Question One Detail Job with a specific venue URL"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Get URL from args or use default
    {url, title} = get_venue_from_args(args)

    IO.puts("🧪 Running Question One Detail Job TEST for venue: #{title}")

    # Get the source ID for Question One
    source = get_question_one_source()

    # Call the detail job with the venue URL
    case TriviaAdvisor.Scraping.Oban.QuestionOneDetailJob.perform(%Oban.Job{
      args: %{
        "url" => url,
        "title" => title,
        "source_id" => source.id
      }
    }) do
      {:ok, result} ->
        IO.puts("✅ Test completed successfully!")
        IO.puts("📊 Result: #{inspect(result)}")
        :ok

      {:error, reason} ->
        IO.puts("❌ Test failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # Get the Question One source ID
  defp get_question_one_source do
    alias TriviaAdvisor.Repo
    alias TriviaAdvisor.Scraping.Source

    # Find the Question One source
    case Repo.get_by(Source, name: "Question One") do
      nil ->
        IO.puts("❌ Question One source not found. Creating it...")

        # Create the source if it doesn't exist
        %Source{}
        |> Source.changeset(%{
          name: "Question One",
          url: "https://www.questionone.com/",
          active: true
        })
        |> Repo.insert!()

      source ->
        source
    end
  end

  # Extract venue from command line arguments
  defp get_venue_from_args(args) do
    url_arg = Enum.find(args, fn arg -> String.starts_with?(arg, "--url=") end)
    title_arg = Enum.find(args, fn arg -> String.starts_with?(arg, "--title=") end)

    url = if url_arg do
      url_arg |> String.replace("--url=", "") |> String.trim()
    else
      # Default URL - update this with a known valid Question One venue URL
      "https://www.questionone.com/venue/view/7702"
    end

    title = if title_arg do
      title_arg |> String.replace("--title=", "") |> String.trim()
    else
      # Default title
      "Sample Question One Venue"
    end

    {url, title}
  end
end

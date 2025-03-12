defmodule Debug do
  require Logger
  alias TriviaAdvisor.Scraping.Helpers.ImageDownloader
  alias TriviaAdvisor.Events.Performer
  import Ecto.Query

  def run do
    # Set up logging
    Logger.configure(level: :debug)

    IO.puts("🔍 Debugging profile image download and save")

    # Test image URL from GeeksWhoDrink
    image_url = "https://s3.amazonaws.com/motherbrain-prod/avatar_1682524400990"
    IO.puts("Image URL: #{image_url}")

    # Try to download the image
    downloaded_image = ImageDownloader.download_performer_image(image_url)
    IO.puts("Downloaded image: #{inspect(downloaded_image)}")

    # Check if image was downloaded
    if downloaded_image do
      # Get the source ID for GeeksWhoDrink
      source = TriviaAdvisor.Repo.one!(from s in TriviaAdvisor.Scraping.Source,
                                      where: s.name == "geeks who drink")

      # Create performer params with the profile image
      performer_params = %{
        name: "Test Performer #{:rand.uniform(1000)}",
        source_id: source.id,
        profile_image: downloaded_image
      }

      IO.puts("Creating performer with params: #{inspect(performer_params)}")

      case Performer.find_or_create(performer_params) do
        {:ok, performer} ->
          IO.puts("✅ Successfully created performer with ID: #{performer.id}")
          IO.puts("Profile image: #{inspect(performer.profile_image)}")

          # Verify by refetching from DB after a short delay to allow the async task to finish
          Process.sleep(1000) # Wait for async file copying
          refetched = TriviaAdvisor.Repo.get(Performer, performer.id)
          IO.puts("Refetched from DB: #{inspect(refetched.profile_image)}")

          # Check if the file was saved to the expected location
          performer_name = performer.name
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]+/, "-")
            |> String.trim("-")

          expected_dir = Path.join(["priv", "static", "uploads", "performers", "#{performer_name}-#{performer.id}"])
          IO.puts("Expected directory: #{expected_dir}")

          # Check if the expected directory exists and has files
          if File.exists?(expected_dir) do
            IO.puts("Directory exists, contents:")
            {:ok, files} = File.ls(expected_dir)
            IO.inspect(files)
          else
            IO.puts("Directory does not exist")
          end

        {:error, changeset} ->
          IO.puts("❌ Failed to create performer:")
          IO.puts(inspect(changeset.errors))
          IO.puts("Full changeset: #{inspect(changeset)}")
      end
    else
      IO.puts("❌ Failed to download image")
    end
  end
end

# Run the debug function
Debug.run()

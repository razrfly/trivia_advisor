defmodule TriviaAdvisor.Uploaders.ProfileImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  # Define original and thumbnail versions
  @versions [:original, :thumb]

  @acl :public_read

  # Whitelist file extensions
  def validate({file, _}) do
    file_extension = case file do
      %{filename: filename} -> filename |> Path.extname() |> String.downcase()
      %{file_name: file_name} -> file_name |> Path.extname() |> String.downcase()
      _ -> ".jpg" # Default
    end

    Enum.member?(~w(.jpg .jpeg .gif .png .webp .avif), file_extension)
  end

  # Define a thumbnail transformation:
  def transform(:thumb, _) do
    {:convert, "-thumbnail 300x300^ -gravity center -extent 300x300"}
  end

  # Storage directory for performer profile images
  def storage_dir(_version, {_file, scope}) do
    performer_id = if is_map(scope) and Map.has_key?(scope, :id), do: scope.id, else: "temp"
    performer_name = if is_map(scope) and Map.has_key?(scope, :name) do
      scope.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
    else
      "temp"
    end

    "uploads/performer_profile_images/#{performer_name}-#{performer_id}"
  end

  # Generate a unique filename
  def filename(version, {file, _scope}) do
    # Get the filename without extension
    file_name = case file do
      %{filename: filename} -> Path.rootname(filename)
      %{file_name: file_name} -> Path.rootname(file_name)
      _ -> "image_#{:rand.uniform(999999)}"
    end

    "#{version}_#{file_name}"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    "https://placehold.co/300x300/png?text=No+Image"
  end
end

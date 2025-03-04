defmodule TriviaAdvisor.Uploaders.ProfileImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition
  require Logger

  # Define original and thumbnail versions
  @versions [:original, :thumb]

  @acl :public_read

  # Whitelist file extensions
  def validate({file, _}) do
    Logger.debug("🔍 Validating file: #{inspect(file)}")
    file_extension = case file do
      %{filename: filename} ->
        ext = filename |> Path.extname() |> String.downcase()
        Logger.debug("📄 File extension from filename: #{ext}")
        ext
      %{file_name: file_name} ->
        ext = file_name |> Path.extname() |> String.downcase()
        Logger.debug("📄 File extension from file_name: #{ext}")
        ext
      _ ->
        Logger.debug("⚠️ No filename or file_name found, defaulting to .jpg")
        ".jpg" # Default
    end

    valid = Enum.member?(~w(.jpg .jpeg .gif .png .webp .avif), file_extension)
    Logger.debug("✅ File validation result: #{valid}")
    valid
  end

  # Define a thumbnail transformation:
  def transform(:thumb, _) do
    Logger.debug("🔄 Transforming thumbnail")
    {:convert, "-thumbnail 300x300^ -gravity center -extent 300x300"}
  end

  # Storage directory for performer profile images
  def storage_dir(_version, {_file, scope}) do
    Logger.debug("📁 Determining storage directory for scope: #{inspect(scope)}")
    performer_id = if is_map(scope) and Map.has_key?(scope, :id), do: scope.id, else: "temp"
    performer_name = if is_map(scope) and Map.has_key?(scope, :name) do
      scope.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
    else
      "temp"
    end

    dir = "uploads/performer_profile_images/#{performer_name}-#{performer_id}"
    Logger.debug("📁 Using storage directory: #{dir}")
    dir
  end

  # Generate a unique filename
  def filename(version, {file, _scope}) do
    Logger.debug("🏷️ Generating filename for version: #{version}, file: #{inspect(file)}")
    # Get the filename without extension
    file_name = case file do
      %{filename: filename} ->
        name = Path.rootname(filename)
        Logger.debug("📄 Using filename: #{name}")
        name
      %{file_name: file_name} ->
        name = Path.rootname(file_name)
        Logger.debug("📄 Using file_name: #{name}")
        name
      _ ->
        name = "image_#{:rand.uniform(999999)}"
        Logger.debug("📄 Using random name: #{name}")
        name
    end

    result = "#{version}_#{file_name}"
    Logger.debug("🏷️ Generated filename: #{result}")
    result
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    Logger.debug("🔗 Using default URL")
    "https://placehold.co/300x300/png?text=No+Image"
  end

  # Callback invoked to determine if the file should be stored
  def should_store?({file, scope}) do
    Logger.debug("❓ Should store file: #{inspect(file)} for scope: #{inspect(scope)}?")
    true
  end
end

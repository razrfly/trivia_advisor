defmodule TriviaAdvisor.Uploaders.ProfileImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition
  require Logger

  # Define original and thumbnail versions
  @versions [:original, :thumb]

  @acl :public_read

  # Whitelist file extensions
  def validate({file, _}) do
    file_extension = case file do
      %{filename: filename} ->
        filename |> Path.extname() |> String.downcase()
      %{file_name: file_name} ->
        file_name |> Path.extname() |> String.downcase()
      _ ->
        ".jpg" # Default
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

    "uploads/performers/#{performer_name}-#{performer_id}"
  end

  # Generate a unique filename
  def filename(version, {file, _scope}) do
    # Get the filename without extension
    file_name = case file do
      %{filename: filename} ->
        Path.rootname(filename)
      %{file_name: file_name} ->
        Path.rootname(file_name)
      _ ->
        "image_#{:rand.uniform(999999)}"
    end

    "#{version}_#{file_name}"
  end

  # Override url/3 to safely handle nil values
  def url(nil, _version, _opts), do: default_url(nil, nil)
  def url(file_and_scope, version, opts) do
    try do
      # This matches what HeroImage does successfully
      if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
        # Get the standard URL from Waffle
        standard_url = super(file_and_scope, version, opts)

        # Get bucket name from env var, with fallback
        bucket = System.get_env("BUCKET_NAME") ||
                 Application.get_env(:waffle, :bucket) ||
                 "trivia-advisor"

        # Get S3 configuration
        s3_config = Application.get_env(:ex_aws, :s3, [])
        host = case s3_config[:host] do
          h when is_binary(h) -> h
          _ -> "fly.storage.tigris.dev"
        end

        # Format path correctly for S3 (remove leading slash)
        s3_path = if is_binary(standard_url) && String.starts_with?(standard_url, "/"),
                  do: String.slice(standard_url, 1..-1//1),
                  else: standard_url

        # Construct the full S3 URL
        if is_binary(s3_path) do
          "https://#{bucket}.#{host}/#{s3_path}"
        else
          default_url(version, nil)
        end
      else
        super(file_and_scope, version, opts)
      end
    rescue
      e ->
        Logger.error("Error in ProfileImage.url/3: #{Exception.message(e)}")
        default_url(version, nil)
    end
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, _scope) do
    "https://placehold.co/300x300/png?text=No+Image"
  end

  # Callback invoked to determine if the file should be stored
  def should_store?({_file, _scope}) do
    true
  end
end

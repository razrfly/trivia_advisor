defmodule TriviaAdvisor.Uploaders.HeroImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original]
  @acl :public_read

  # Whitelist file extensions
  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    ~w(.jpg .jpeg .png) |> Enum.member?(file_extension)
  end

  # Define the storage directory
  def storage_dir(_version, {_file, event}) do
    "uploads/events/#{event.id}/hero"
  end

  # Generate a unique filename
  def filename(version, {file, _event}) do
    file_name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{file_name}_#{version}"
  end
end

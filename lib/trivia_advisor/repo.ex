defmodule TriviaAdvisor.Repo do
  use Ecto.Repo,
    otp_app: :trivia_advisor,
    adapter: Ecto.Adapters.Postgres

  use Ecto.SoftDelete.Repo

  require Logger

  @doc """
  This function wraps Repo.delete/1 to call before_delete callbacks
  defined on schemas before deleting the record.

  Usage: Replace calls to Repo.delete/1 with Repo.delete_with_callbacks/1
  """
  def delete_with_callbacks(struct, opts \\ []) do
    call_before_delete_callback(struct)
    delete(struct, opts)
  end

  @doc """
  This function wraps Repo.delete!/1 to call before_delete callbacks
  defined on schemas before deleting the record.

  Usage: Replace calls to Repo.delete!/1 with Repo.delete_with_callbacks!/1
  """
  def delete_with_callbacks!(struct, opts \\ []) do
    call_before_delete_callback(struct)
    delete!(struct, opts)
  end

  # Private helper for calling before_delete callbacks
  defp call_before_delete_callback(struct) do
    try do
      schema_module = struct.__struct__

      if function_exported?(schema_module, :before_delete, 1) do
        Logger.debug("Calling before_delete callback for #{inspect(schema_module)}")
        schema_module.before_delete(struct)
      end
    rescue
      e ->
        Logger.error("Error in before_delete callback: #{Exception.message(e)}")
    end
  end
end

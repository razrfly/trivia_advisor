defmodule TriviaAdvisorWeb.Components.JsonLdComponent do
  @moduledoc """
  Component for rendering JSON-LD structured data in the page head.
  """

  use Phoenix.Component

  @doc """
  Renders JSON-LD structured data in a script tag.

  ## Examples

      <.json_ld_script json_ld={json_ld_string} />
  """
  attr :json_ld, :string, required: true, doc: "JSON-LD data as a string"

  def json_ld_script(assigns) do
    ~H"""
    <script type="application/ld+json">
      <%= raw(@json_ld) %>
    </script>
    """
  end

  defp raw(str), do: Phoenix.HTML.raw(str)
end

defmodule TriviaAdvisor.Utils.Slug do
  @moduledoc """
  Utility module for generating URL-friendly slugs from strings.
  """

  @doc """
  Converts a string into a URL-friendly slug.

  ## Examples

      iex> TriviaAdvisor.Utils.Slug.slugify("Hello World!")
      "hello-world"

      iex> TriviaAdvisor.Utils.Slug.slugify("United Kingdom")
      "united-kingdom"
  """
  def slugify(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end

  def slugify(_), do: ""
end

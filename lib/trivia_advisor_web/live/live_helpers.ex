defmodule TriviaAdvisorWeb.LiveHelpers do
  @moduledoc """
  Helper functions for LiveView modules, including Cloudflare header handling.
  """

  # Add headers to LiveView socket for Cloudflare
  def cloudflare_socket_connect_info(socket, connect_info) do
    headers = Enum.into(connect_info.x_headers, %{})

    socket
    |> maybe_assign_real_ip(headers)
    |> maybe_assign_cf_headers(headers)
  end

  defp maybe_assign_real_ip(socket, headers) do
    case Map.get(headers, "cf-connecting-ip") do
      nil -> socket
      real_ip -> Phoenix.LiveView.assign(socket, :real_ip, real_ip)
    end
  end

  defp maybe_assign_cf_headers(socket, headers) do
    cf_headers = headers
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, "cf-") end)
    |> Enum.into(%{})

    Phoenix.LiveView.assign(socket, :cf_headers, cf_headers)
  end
end

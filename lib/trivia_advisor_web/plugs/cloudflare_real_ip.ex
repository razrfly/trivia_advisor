defmodule TriviaAdvisorWeb.Plugs.CloudflareRealIp do
  @moduledoc """
  A plug that extracts the real IP address from Cloudflare's CF-Connecting-IP header.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "cf-connecting-ip") do
      [real_ip | _] ->
        conn
        |> put_req_header("x-real-ip", real_ip)
        |> put_req_header("x-forwarded-for", real_ip)
      _ ->
        conn
    end
  end
end

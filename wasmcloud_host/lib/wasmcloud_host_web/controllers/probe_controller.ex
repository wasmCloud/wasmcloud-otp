defmodule WasmcloudHostWeb.ProbeController do
  use WasmcloudHostWeb, :controller

  def ready(conn, _params) do
    json(conn, %{ready: true})
  end

  def live(conn, _params) do
    json(conn, %{live: true})
  end
end

defmodule WasmcloudHostWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :wasmcloud_host

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_wasmcloud_host_key",
    signing_salt: "oIfMIYiq"
  ]

  socket("/socket", WasmcloudHostWeb.UserSocket,
    websocket: true,
    longpoll: false
  )

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :wasmcloud_host,
    gzip: false,
    only: ~w(assets css fonts images js coreui favicon.ico robots.txt)
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(WasmcloudHostWeb.Router)

  def init(_key, config) do
    host = System.get_env("WASMCLOUD_DASHBOARD_HOST")
    port = System.get_env("WASMCLOUD_DASHBOARD_PORT", "4000") |> String.to_integer()

    case {host, port} do
      {nil, nil} ->
        {:ok, config}

      {host, nil} ->
        {:ok, config |> Keyword.put(:url, host: host)}

      {nil, port} ->
        {:ok, config |> Keyword.put(:url, port: port) |> Keyword.put(:http, port: port)}

      {host, port} ->
        {:ok,
         config
         |> Keyword.put(:url, host: host, port: port)
         |> Keyword.put(:http, port: port)}
    end
  end
end

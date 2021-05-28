defmodule WasmcloudHost.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      WasmcloudHostWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: WasmcloudHost.PubSub},
      # Start the Endpoint (http/https)
      WasmcloudHostWeb.Endpoint,
      # Start a worker by calling: WasmcloudHost.Worker.start_link(arg)
      # {WasmcloudHost.Worker, arg}
      WasmcloudHost.Lattice.StateMonitor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WasmcloudHost.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    WasmcloudHostWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

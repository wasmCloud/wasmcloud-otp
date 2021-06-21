defmodule HostCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  def start(_type, _args) do
    # Ensure NATS is connected before starting children
    Logger.info("Configuring NATS connections")

    retrieve_nats_env()
    |> start_gnat()

    children = [
      # Starts a worker by calling: HostCore.Worker.start_link(arg)
      # {HostCore.Worker, arg}
      {Registry, keys: :unique, name: Registry.ProviderRegistry},
      {Registry, keys: :duplicate, name: Registry.ActorRegistry},
      {HostCore.Host, strategy: :one_for_one, name: Host},
      {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      {HostCore.Actors.ActorSupervisor, strategy: :one_for_one, name: ActorRoot},
      {HostCore.LinkdefsManager, strategy: :one_for_one, name: LinkdefsManager},
      {HostCore.ClaimsManager, strategy: :one_for_one, name: ClaimsManager}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HostCore.Supervisor]

    Logger.info("Starting Host Core")
    Supervisor.start_link(children, opts)
  end

  defp retrieve_nats_env() do
    rpc_host =
      case System.get_env("WASMCLOUD_RPC_HOST") do
        nil -> '0.0.0.0'
        host -> host
      end

    rpc_port =
      case System.get_env("WASMCLOUD_RPC_PORT") do
        nil -> 4222
        port -> String.to_integer(port)
      end

    ctl_host =
      case System.get_env("WASMCLOUD_CTL_HOST") do
        nil -> '0.0.0.0'
        host -> host
      end

    ctl_port =
      case System.get_env("WASMCLOUD_CTL_PORT") do
        nil -> 4222
        port -> String.to_integer(port)
      end

    {rpc_host, rpc_port, ctl_host, ctl_port}
  end

  defp start_gnat({rpc_host, rpc_port, ctl_host, ctl_port}) do
    :ok = lattice_connect(rpc_host, rpc_port)
    :ok = control_connect(ctl_host, ctl_port)
  end

  defp lattice_connect(rpc_host, rpc_port) do
    case Gnat.start_link(%{host: rpc_host, port: rpc_port}, name: :lattice_nats) do
      {:ok, _gnat} ->
        :ok

      {:error, :econnrefused} ->
        Logger.warn(
          "Failed to connect to lattice at #{rpc_host}:#{rpc_port}, retrying in 1 second..."
        )

        Process.sleep(1000)
        lattice_connect(rpc_host, rpc_port)
    end
  end

  defp control_connect(ctl_host, ctl_port) do
    case Gnat.start_link(%{host: ctl_host, port: ctl_port}, name: :control_nats) do
      {:ok, _gnat} ->
        :ok

      {:error, :econnrefused} ->
        Logger.warn(
          "Failed to connect to control interface at #{ctl_host}:#{ctl_port}, retrying in 1 second..."
        )

        Process.sleep(1000)
        control_connect(ctl_host, ctl_port)
    end
  end
end

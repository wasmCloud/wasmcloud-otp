defmodule HostCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  def config!() do
    providers = [
      %Vapor.Provider.Env{
        bindings: [
          {:rpc_host, "WASMCLOUD_RPC_HOST", default: "0.0.0.0"},
          {:rpc_port, "WASMCLOUD_RPC_PORT", default: 4222, map: &String.to_integer/1},
          {:ctl_host, "WASMCLOUD_CTL_HOST", default: "0.0.0.0"},
          {:ctl_port, "WASMCLOUD_CTL_PORT", default: 4222, map: &String.to_integer/1}
        ]
      }
    ]

    Vapor.load!(providers)
  end

  def start(_type, _args) do
    config = config!()

    children = [
      # Starts a worker by calling: HostCore.Worker.start_link(arg)
      # {HostCore.Worker, arg}
      {Registry, keys: :unique, name: Registry.ProviderRegistry},
      {Registry, keys: :duplicate, name: Registry.ActorRegistry},
      {HostCore.Host, strategy: :one_for_one, name: Host},
      {HostCore.NatsSupervisor, [config]}
      # {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      # {HostCore.Actors.ActorSupervisor, strategy: :one_for_one, name: ActorRoot},
      # {HostCore.LinkdefsManager, strategy: :one_for_one, name: LinkdefsManager},
      # {HostCore.ClaimsManager, strategy: :one_for_one, name: ClaimsManager}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HostCore.Supervisor]

    Logger.info("Starting Host Core")
    Supervisor.start_link(children, opts)
  end
end

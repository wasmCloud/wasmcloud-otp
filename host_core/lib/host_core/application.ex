defmodule HostCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  @prefix_var "WASMCLOUD_LATTICE_PREFIX"
  @default_prefix "default"

  def config!() do
    providers = [
      %Vapor.Provider.Env{
        bindings: [
          {:lattice_prefix, @prefix_var, default: @default_prefix}
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
      {HostCore.Host, lattice_prefix: config.lattice_prefix},
      {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      {HostCore.Actors.ActorSupervisor, strategy: :one_for_one, name: ActorRoot},
      {HostCore.Linkdefs.Manager, strategy: :one_for_one, name: LinkdefsManager},
      {HostCore.Claims.Manager, strategy: :one_for_one, name: ClaimsManager},
      # Handle advertised link definitions and corresponding queries
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :lattice_nats,
           module: HostCore.Linkdefs.Server,
           subscription_topics: [
             %{topic: "wasmbus.rpc.#{config.lattice_prefix}.linkdefs.put"},
             %{topic: "wasmbus.rpc.#{config.lattice_prefix}.linkdefs.del"},
             %{
               topic: "wasmbus.rpc.#{config.lattice_prefix}.linkdefs.get",
               queue_group: "wasmbus.rpc.#{config.lattice_prefix}.linkdefs.get"
             }
           ]
         }},
        id: :linkdefs_consumer_supervisor
      ),
      # Handle advertised PK->Claims maps and corresponding queries
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :lattice_nats,
           module: HostCore.Claims.Server,
           subscription_topics: [
             %{topic: "wasmbus.rpc.#{config.lattice_prefix}.claims.put"},
             %{
               topic: "wasmbus.rpc.#{config.lattice_prefix}.claims.get",
               queue_group: "wasmbus.rpc.#{config.lattice_prefix}.claims.get"
             }
           ]
         }},
        id: :claims_consumer_supervisor
      ),
      # Handle advertised OCI->public key reference maps and corresponding queries
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :lattice_nats,
           module: HostCore.Refmaps.Server,
           subscription_topics: [
             %{topic: "wasmbus.rpc.#{config.lattice_prefix}.refmaps.put"},
             %{
               topic: "wasmbus.rpc.#{config.lattice_prefix}.refmaps.get",
               queue_group: "wasmbus.rpc.#{config.lattice_prefix}.refmaps.get"
             }
           ]
         }},
        id: :refmaps_consumer_supervisor
      )
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HostCore.Supervisor]

    Logger.info("Starting Host Core")
    Supervisor.start_link(children, opts)
  end
end

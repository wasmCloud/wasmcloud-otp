defmodule HostCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  @prefix_var "WASMCLOUD_LATTICE_PREFIX"
  @hostkey_var "WASMCLOUD_HOST_KEY"
  @hostseed_var "WASMCLOUD_HOST_SEED"
  @default_prefix "default"

  def config!() do
    {host_key, host_seed} = HostCore.WasmCloud.Native.generate_key(:server)
    {def_cluster_key, def_cluster_seed} = HostCore.WasmCloud.Native.generate_key(:cluster)

    providers = [
      %Vapor.Provider.Env{
        bindings: [
          {:host_key, @hostkey_var, default: host_key},
          {:host_seed, @hostseed_var, default: host_seed},
          {:lattice_prefix, @prefix_var, default: @default_prefix},
          {:rpc_host, "WASMCLOUD_RPC_HOST", default: "0.0.0.0"},
          {:rpc_port, "WASMCLOUD_RPC_PORT", default: 4222, map: &String.to_integer/1},
          {:rpc_seed, "WASMCLOUD_RPC_SEED", default: ""},
          {:rpc_jwt, "WASMCLOUD_RPC_JWT", default: ""},
          {:prov_rpc_host, "WASMCLOUD_PROV_RPC_HOST", default: "0.0.0.0"},
          {:prov_rpc_port, "WASMCLOUD_PROV_RPC_PORT", default: 4222, map: &String.to_integer/1},
          {:prov_rpc_seed, "WASMCLOUD_PROV_RPC_SEED", default: ""},
          {:prov_rpc_jwt, "WASMCLOUD_PROV_RPC_JWT", default: ""},
          {:ctl_host, "WASMCLOUD_CTL_HOST", default: "0.0.0.0"},
          {:ctl_port, "WASMCLOUD_CTL_PORT", default: 4222, map: &String.to_integer/1},
          {:ctl_seed, "WASMCLOUD_CTL_SEED", default: ""},
          {:ctl_jwt, "WASMCLOUD_CTL_JWT", default: ""},
          {:cluster_seed, "WASMCLOUD_CLUSTER_SEED", default: def_cluster_seed},
          {:cluster_issuers, "WASMCLOUD_CLUSTER_ISSUERS", default: def_cluster_key},
          {:provider_delay, "WASMCLOUD_PROV_SHUTDOWN_DELAY_MS",
           default: 300, map: &String.to_integer/1}
        ]
      }
    ]

    Vapor.load!(providers)
  end

  def start(_type, _args) do
    config = config!()

    children = [
      # {HostCore.Worker, arg}
      {Registry, keys: :unique, name: Registry.ProviderRegistry},
      {Registry, keys: :duplicate, name: Registry.ActorRegistry},
      {HostCore.Host, config},
      {HostCore.HeartbeatEmitter, config},
      {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      {HostCore.Actors.ActorSupervisor, strategy: :one_for_one, name: ActorRoot},
      {HostCore.Claims.Manager, strategy: :one_for_one, name: ClaimsManager},
      {HostCore.Linkdefs.Manager, strategy: :one_for_one, name: LinkdefsManager},
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
      ),
      # Handle lattice control interface requests
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :control_nats,
           module: HostCore.ControlInterface.Server,
           subscription_topics: [
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.cmd.>"},
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.get.>"},
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.auction.>"}
           ]
         }},
        id: :latticectl_consumer_supervisor
      )
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HostCore.Supervisor]

    Logger.info("Starting Host Core")
    Supervisor.start_link(children, opts)
  end
end

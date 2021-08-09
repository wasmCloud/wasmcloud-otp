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

    s =
      Hashids.new(
        salt: "lc_deliver_inbox",
        min_len: 2
      )

    hid = Hashids.encode(s, Enum.random(1..4_294_967_295))

    providers = [
      %Vapor.Provider.Env{
        bindings: [
          {:cache_deliver_inbox, "_DI", default: "_INBOX.#{hid}"},
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
           default: 300, map: &String.to_integer/1},
          {:allow_latest, "WASMCLOUD_OCI_ALLOW_LATEST", default: false, map: &String.to_atom/1},
          {:allowed_insecure, "WASMCLOUD_OCI_ALLOWED_INSECURE",
           default: [], map: &String.split(&1, ",")}
        ]
      }
    ]

    Vapor.load!(providers)
  end

  def start(_type, _args) do
    config = config!()

    children = [
      {Registry, keys: :unique, name: Registry.ProviderRegistry},
      {Registry, keys: :duplicate, name: Registry.ActorRegistry},
      Supervisor.child_spec(
        {Gnat.ConnectionSupervisor, HostCore.Nats.control_connection_settings(config)},
        id: :control_connection_supervisor
      ),
      Supervisor.child_spec(
        {Gnat.ConnectionSupervisor, HostCore.Nats.rpc_connection_settings(config)},
        id: :rpc_connection_supervisor
      ),
      {HostCore.HeartbeatEmitter, config},
      {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      {HostCore.Actors.ActorSupervisor,
       strategy: :one_for_one,
       allow_latest: config.allow_latest,
       allowed_insecure: config.allowed_insecure},      
      # Handle lattice control interface requests
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :control_nats,
           module: HostCore.ControlInterface.Server,
           subscription_topics: [
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.cmd.#{config.host_key}.*"},
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.ping.hosts"},
             %{
               topic: "wasmbus.ctl.#{config.lattice_prefix}.linkdefs.*",
               queue_group: "wasmbus.ctl.#{config.lattice_prefix}"
             },
             %{
               topic: "wasmbus.ctl.#{config.lattice_prefix}.get.>",
               queue_group: "wasmbus.ctl.#{config.lattice_prefix}"
             },
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.auction.>"}
           ]
         }},
        id: :latticectl_consumer_supervisor
      ),
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :control_nats,
           module: HostCore.Jetstream.CacheLoader,
           subscription_topics: [
             %{topic: "#{config.cache_deliver_inbox}"}
           ]
         }},
        id: :cacheloader_consumer_supervisor
      ),
      {HostCore.Host, config},
      {HostCore.Jetstream.Client, config}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HostCore.Supervisor]

    Logger.info("Starting Host Core")
    Supervisor.start_link(children, opts)
  end
end

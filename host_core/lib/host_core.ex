defmodule HostCore do
  @moduledoc """
  `HostCore` Application.
  """
  require Logger
  use Application

  def start(_type, _args) do
    config = Vapor.load!(HostCore.ConfigPlan)
    config = post_process_config(config)

    children = mount_supervisor_tree(config)

    opts = [strategy: :one_for_one, name: HostCore.Supervisor]

    Logger.info("Starting Host Core")
    Supervisor.start_link(children, opts)
  end

  defp mount_supervisor_tree(config) do
    [
      {Registry, keys: :unique, name: Registry.ProviderRegistry},
      {Registry, keys: :duplicate, name: Registry.ActorRegistry},
      {Registry,
       keys: :duplicate,
       name: Registry.EventMonitorRegistry,
       partitions: System.schedulers_online()},
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
               topic: "wasmbus.ctl.#{config.lattice_prefix}.get.*",
               queue_group: "wasmbus.ctl.#{config.lattice_prefix}"
             },
             %{
               topic: "wasmbus.ctl.#{config.lattice_prefix}.get.#{config.host_key}.inv"
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
  end

  defp post_process_config(config) do
    config = Map.put(config, :cluster_adhoc, false)
    config = Map.put(config, :cluster_key, "")

    s =
      Hashids.new(
        salt: "lc_deliver_inbox",
        min_len: 2
      )

    hid = Hashids.encode(s, Enum.random(1..4_294_967_295))
    config = Map.put(config, :cache_deliver_inbox, "_INBOX.#{hid}")

    {def_cluster_key, def_cluster_seed} = HostCore.WasmCloud.Native.generate_key(:cluster)
    # we're generating the key, so we know this is going to work
    {:ok, issuer_key} = HostCore.WasmCloud.Native.pk_from_seed(def_cluster_seed)

    config =
      if config.cluster_seed == "" do
        %{
          config
          | cluster_seed: def_cluster_seed,
            cluster_key: def_cluster_key,
            cluster_issuers: [issuer_key],
            cluster_adhoc: true
        }
      else
        case HostCore.WasmCloud.Native.pk_from_seed(config.cluster_seed) do
          {:ok, pk} ->
            issuers = ensure_contains(config.cluster_issuers, pk)

            %{
              config
              | cluster_seed: config.cluster_seed,
                cluster_key: config.cluster_key,
                cluster_issuers: issuers,
                cluster_adhoc: false
            }

          {:error, err} ->
            Logger.error(
              "Invalid cluster seed '#{config.cluster_seed}': #{err}, falling back to ad hoc cluster key"
            )

            %{
              config
              | cluster_seed: def_cluster_seed,
                cluster_key: def_cluster_key,
                cluster_issuers: [issuer_key],
                cluster_adhoc: true
            }
        end
      end

    config
  end

  defp ensure_contains(list, item) do
    if Enum.member?(list, item) do
      list
    else
      [item | list]
    end
  end
end

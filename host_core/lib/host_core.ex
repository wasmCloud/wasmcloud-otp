defmodule HostCore do
  @moduledoc """
  `HostCore` Application.
  """
  require Logger
  use Application

  def start(_type, _args) do
    config = Vapor.load!(HostCore.ConfigPlan)

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
end

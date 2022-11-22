defmodule HostCore.Lattice.LatticeSupervisor do
  @moduledoc """
  The lattice supervisor is responsible for starting the following children:
  * A gnat connection supervisor for: control and rpc connections
  * A consumer supervisor for the control interface subscription(s)
  """

  use Supervisor

  require Logger

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config,
      name: HostCore.Lattice.LatticeRoot.via_tuple(config.lattice_prefix)
    )
  end

  @impl true
  def init(config) do
    Logger.info("Starting lattice supervisor for '#{config.lattice_prefix}'")

    children =
      [
        Supervisor.child_spec(
          {Gnat.ConnectionSupervisor, HostCore.Nats.control_connection_settings(config)},
          id: HostCore.Nats.control_connection(config.lattice_prefix)
        ),
        Supervisor.child_spec(
          {Gnat.ConnectionSupervisor, HostCore.Nats.rpc_connection_settings(config)},
          id: HostCore.Nats.rpc_connection(config.lattice_prefix)
        ),
        Supervisor.child_spec(
          {Gnat.ConsumerSupervisor,
           %{
             connection_name: HostCore.Nats.control_connection(config.lattice_prefix),
             module: HostCore.ControlInterface.LatticeServer,
             subscription_topics: [
               %{topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.registries.put"},
               #  %{
               #    topic:
               #      "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.cmd.#{config.host_key}.*"
               #  },
               %{topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.ping.hosts"},
               %{
                 topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.linkdefs.*",
                 queue_group: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}"
               },
               %{
                 topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.get.*",
                 queue_group: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}"
               },
               #  %{
               #    topic:
               #      "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.get.#{config.host_key}.inv"
               #  },
               %{topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.auction.>"}
             ]
           }},
          id: String.to_atom("#{config.lattice_prefix}-ctl-consumer")
        ),
        Supervisor.child_spec(
          {Gnat.ConsumerSupervisor,
           %{
             connection_name: HostCore.Nats.control_connection(config.lattice_prefix),
             module: HostCore.Jetstream.CacheLoader,
             subscription_topics: [
               %{topic: "#{config.cache_deliver_inbox}"}
             ]
           }},
          id: String.to_atom("#{config.lattice_prefix}-ctl-cacheloader")
        ),
        Supervisor.child_spec(
          {HostCore.Jetstream.Client, config},
          id: String.to_atom("#{config.lattice_prefix}-jsclient")
        )
      ] ++ HostCore.Policy.Manager.spec(config.lattice_prefix)

    ct = HostCore.Claims.Manager.claims_table_atom(config.lattice_prefix)
    ca = HostCore.Claims.Manager.callalias_table_atom(config.lattice_prefix)
    lt = HostCore.Linkdefs.Manager.table_atom(config.lattice_prefix)
    rt = HostCore.Refmaps.Manager.table_atom(config.lattice_prefix)

    if :ets.info(ct) == :undefined do
      :ets.new(ct, [:named_table, :set, :public])
    end

    if :ets.info(lt) == :undefined do
      :ets.new(lt, [:named_table, :set, :public])
    end

    if :ets.info(rt) == :undefined do
      :ets.new(rt, [:named_table, :set, :public])
    end

    if :ets.info(ca) == :undefined do
      :ets.new(ca, [:named_table, :set, :public])
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

  def host_pids_in_lattice(lattice_prefix) do
    pids =
      Registry.select(Registry.HostRegistry, [
        {{:"$1", :"$2", :"$3"}, [{:==, :"$3", lattice_prefix}], [{{:"$2"}}]}
      ])

    Enum.map(pids, fn {e} -> e end)
  end

  def hosts_in_lattice(lattice_prefix) do
    Registry.select(Registry.HostRegistry, [
      {{:"$1", :"$2", :"$3"}, [{:==, :"$3", lattice_prefix}], [{{:"$1", :"$2"}}]}
    ])
  end
end

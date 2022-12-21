defmodule HostCore.Lattice.LatticeSupervisor do
  @moduledoc """
  The lattice supervisor is responsible for starting the following children:
  * A gnat connection supervisor for: control and rpc connections
  * A consumer supervisor for the control interface subscription(s)
  """

  use Supervisor

  alias HostCore.Lattice.LatticeRoot
  alias HostCore.Vhost.VirtualHost

  require Logger

  @spec start_link(HostCore.Vhost.Configuration.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: LatticeRoot.via_tuple(config.lattice_prefix))
  end

  # Uses the same strongly typed host configuration as other supervisors in the hierarchy
  # (though it only cares about the lattice info)
  @impl true
  def init(config) do
    Logger.metadata(lattice_prefix: config.lattice_prefix)

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
               %{topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.ping.hosts"},
               %{
                 topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.linkdefs.*",
                 queue_group: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}"
               },
               %{
                 topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.get.*",
                 queue_group: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}"
               },
               %{topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.auction.>"}
             ]
           }},
          id: String.to_atom("#{config.lattice_prefix}-ctl-consumer")
        ),
        Supervisor.child_spec(
          {Gnat.ConsumerSupervisor,
           %{
             connection_name: HostCore.Nats.control_connection(config.lattice_prefix),
             module: HostCore.Jetstream.MetadataCacheLoader,
             subscription_topics: [
               %{topic: "#{config.metadata_deliver_inbox}"}
             ]
           }},
          id: String.to_atom("#{config.lattice_prefix}-ctl-cacheloader")
        ),
        Supervisor.child_spec(
          {HostCore.Jetstream.Client, config},
          id: String.to_atom("#{config.lattice_prefix}-jsclient")
        )
      ] ++ HostCore.Policy.Manager.spec(config.lattice_prefix)

    ensure_ets_tables_exist(config)

    Supervisor.init(children, strategy: :one_for_one)
  end

  # The following two functions make use of ETS selects (registries sit on top of :ets tables
  # for more information on ETS select syntax:
  # https://www.erlang.org/doc/man/ets.html#select-1
  # https://elixirschool.com/en/lessons/storage/ets#data-retrieval-6
  #
  # tl;dr: A -{source indicators}, B - {predicates}, C - {colums/data to actually return}
  # SELECT C from A where B

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

  @spec config_for_lattice_prefix(lattice_prefix :: String.t()) ::
          HostCore.Vhost.Configuration.t() | nil
  def config_for_lattice_prefix(lattice_prefix) do
    pids = host_pids_in_lattice(lattice_prefix)

    if length(pids) > 0 do
      pids
      |> List.first()
      |> VirtualHost.config()
    else
      nil
    end
  end

  @spec ensure_ets_tables_exist(config :: HostCore.Vhost.Configuration.t()) :: nil
  defp ensure_ets_tables_exist(config) do
    claims = HostCore.Claims.Manager.claims_table_atom(config.lattice_prefix)
    call_alias = HostCore.Claims.Manager.callalias_table_atom(config.lattice_prefix)
    linkdefs = HostCore.Linkdefs.Manager.table_atom(config.lattice_prefix)
    refmaps = HostCore.Refmaps.Manager.table_atom(config.lattice_prefix)

    if :ets.info(claims) == :undefined do
      :ets.new(claims, [:named_table, :set, :public])
    end

    if :ets.info(linkdefs) == :undefined do
      :ets.new(linkdefs, [:named_table, :set, :public])
    end

    if :ets.info(refmaps) == :undefined do
      :ets.new(refmaps, [:named_table, :set, :public])
    end

    if :ets.info(call_alias) == :undefined do
      :ets.new(call_alias, [:named_table, :set, :public])
    end
  end
end

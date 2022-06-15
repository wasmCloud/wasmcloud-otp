defmodule HostCore.Actors.ActorRpcSupervisor do
  require Logger
  use Supervisor

  def start_link(state) do
    Supervisor.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(_opts) do
    Process.flag(:trap_exit, true)
    Supervisor.init([], strategy: :one_for_one)
  end

  defp via_tuple(pk) do
    {:via, Registry, {Registry.ActorRpcSubscribers, pk, []}}
  end

  def stop_rpc_subscriber(public_key) do
    if !Application.get_env(:host_core, :retain_rpc_subscriptions, false) do
      Logger.debug("Terminating RPC subscriber for actor #{public_key}")
      Supervisor.terminate_child(__MODULE__, via_tuple(public_key))
    end
  end

  def start_or_reuse_consumer_supervisor(claims) do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.#{claims.public_key}"

    cs_settings = %{
      connection_name: :lattice_nats,
      module: HostCore.Actors.ActorRpcServer,
      subscription_topics: [
        %{topic: topic, queue_group: topic}
      ]
    }

    spec =
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor, cs_settings},
        id: via_tuple(claims.public_key)
      )

    case Supervisor.start_child(
           __MODULE__,
           spec
         ) do
      {:ok, _v} ->
        Logger.debug("Starting consumer supervisor for actor RPC #{claims.public_key}")

      {:error, {:already_started, _pid}} ->
        Logger.debug("Reusing existing consumer supervisor for actor RPC #{claims.public_key}")

      {:error, :already_present} ->
        Logger.debug("Reusing existing consumer supervisor for actor RPC #{claims.public_key}")

      {:error, e} ->
        Logger.error(
          "Failed to start consumer supervisor for actor RPC #{claims.public_key}: #{inspect(e)}"
        )
    end
  end
end

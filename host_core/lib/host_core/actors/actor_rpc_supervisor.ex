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
    case Supervisor.terminate_child(__MODULE__, via_tuple(public_key)) do
      :ok ->
        case Supervisor.delete_child(__MODULE__, via_tuple(public_key)) do
          :ok ->
            Logger.debug("Terminating RPC subscriber for actor #{public_key}")

          {:error, e} ->
            Logger.error("Failed to delete RPC subscriber for actor #{public_key}: #{inspect(e)}")
        end

      {:error, e} ->
        Logger.error("Failed to terminate RPC subscriber for actor #{public_key}: #{inspect(e)}")
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

    spec_id = via_tuple(claims.public_key)

    spec =
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor, cs_settings},
        id: spec_id
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
        case Supervisor.restart_child(HostCore.Actors.ActorRpcSupervisor, spec_id) do
          {:ok, _v} ->
            Logger.debug(
              "Restarting existing consumer supervisor for actor RPC #{claims.public_key}"
            )

          {:error, e} ->
            Logger.error(
              "Failed to restart consumer supervisor for actor RPC #{claims.public_key}: #{inspect(e)}"
            )
        end

      {:error, e} ->
        Logger.error(
          "Failed to start consumer supervisor for actor RPC #{claims.public_key}: #{inspect(e)}"
        )
    end
  end
end

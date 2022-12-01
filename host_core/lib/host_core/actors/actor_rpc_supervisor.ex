defmodule HostCore.Actors.ActorRpcSupervisor do
  @moduledoc """
  Supervisor module that is responsible for managing all of the RPC supervisors for all actors.
  """
  require Logger
  use Supervisor

  def start_link(state) do
    Supervisor.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(_opts) do
    Supervisor.init([], strategy: :one_for_one)
  end

  defp via_tuple(prefix, pk) do
    {:via, Registry, {Registry.ActorRpcSubscribers, "#{prefix}-#{pk}", []}}
  end

  def stop_rpc_subscriber(lattice_prefix, public_key) do
    case Supervisor.terminate_child(__MODULE__, via_tuple(lattice_prefix, public_key)) do
      :ok ->
        case Supervisor.delete_child(__MODULE__, via_tuple(lattice_prefix, public_key)) do
          :ok ->
            Logger.debug("Terminating RPC subscriber for actor #{public_key}")

          {:error, e} ->
            Logger.error("Failed to delete RPC subscriber for actor #{public_key}: #{inspect(e)}")
        end

      {:error, e} ->
        Logger.error("Failed to terminate RPC subscriber for actor #{public_key}: #{inspect(e)}")
    end
  end

  def start_or_reuse_consumer_supervisor(lattice_prefix, claims) do
    topic = "wasmbus.rpc.#{lattice_prefix}.#{claims.public_key}"

    cs_settings = %{
      connection_name: HostCore.Nats.control_connection(lattice_prefix),
      module: HostCore.Actors.ActorRpcServer,
      subscription_topics: [
        %{topic: topic, queue_group: topic}
      ]
    }

    spec_id = via_tuple(lattice_prefix, claims.public_key)

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
        Logger.debug(
          "Starting consumer supervisor for actor RPC #{claims.public_key} on lattice '#{lattice_prefix}'"
        )

      {:error, {:already_started, _pid}} ->
        Logger.debug(
          "Reusing existing consumer supervisor for actor RPC #{claims.public_key}, lattice '#{lattice_prefix}'"
        )

      {:error, :already_present} ->
        case Supervisor.restart_child(HostCore.Actors.ActorRpcSupervisor, spec_id) do
          {:ok, _v} ->
            Logger.debug(
              "Restarting existing consumer supervisor for actor RPC #{claims.public_key}, lattice '#{lattice_prefix}'"
            )

          {:error, e} ->
            Logger.error(
              "Failed to restart consumer supervisor for actor RPC #{claims.public_key}: #{inspect(e)}. Invocations for this actor may not be handled."
            )
        end

      {:error, e} ->
        Logger.error(
          "Failed to start consumer supervisor for actor RPC #{claims.public_key}: #{inspect(e)}. Invocations for this actor may not be handled."
        )
    end
  end
end

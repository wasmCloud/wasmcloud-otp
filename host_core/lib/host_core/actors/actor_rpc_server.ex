defmodule HostCore.Actors.ActorRpcServer do
  @moduledoc """
  The actor RPC server is a Gnat.Server process that is listening to incoming messages on an actor's RPC subscription
  topic, which is a queue subscription derived from the actor's public key. This server will attempt to deliver inbound
  messages to multiple instances of the same actor on the same virtual host in round robin fashion.

  This consumer is started when an actor starts and is stopped when the _last instance_ of that actor terminates.
  """
  require Logger
  alias HostCore.Actors.CallCounter
  alias HostCore.Lattice.LatticeSupervisor
  use Gnat.Server

  def request(
        %{
          body: _body,
          reply_to: _reply_to,
          topic: topic
        } = msg
      ) do
    tokens = String.split(topic, ".")

    if length(tokens) != 4 do
      # This could cause a timeout for a waiting consumer, but that's "ok" since
      # nobody should send on a malformed RPC topic anyway
      :ok
    else
      ["wasmbus", "rpc", lattice_prefix, actor_pk] = tokens

      host_candidates =
        lattice_prefix
        |> LatticeSupervisor.hosts_in_lattice()
        |> Enum.map(fn {h, _pid} -> h end)

      case Registry.lookup(Registry.ActorRegistry, actor_pk) do
        [] ->
          {:error, "Actor #{actor_pk} is not running. RPC call skipped."}

        actors ->
          eligible_actors =
            Enum.filter(actors, fn {_pid, host_id} -> host_id in host_candidates end)

          next_index = CallCounter.read_and_increment(actor_pk, lattice_prefix)
          {pid, _value} = Enum.at(eligible_actors, rem(next_index, length(eligible_actors)))

          case GenServer.call(pid, {:handle_incoming_rpc, msg}) do
            {:ok, resp} ->
              {:reply, resp}

            _ ->
              Logger.error("Failed to invoke actor with incoming RPC, actor may not be running")
              :ok
          end
      end
    end
  end

  def error(
        %{gnat: gnat, reply_to: reply_to},
        error
      ) do
    Logger.error("Actor RPC handler failure: #{inspect(error)}")

    ir = %{
      msg: <<>>,
      invocation_id: "",
      error: "Failed to handle actor RPC: #{inspect(error)}",
      instance_id: ""
    }

    HostCore.Nats.safe_pub(
      gnat,
      reply_to,
      ir |> Msgpax.pack!() |> IO.iodata_to_binary()
    )
  end
end

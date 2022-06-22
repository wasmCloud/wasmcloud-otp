defmodule HostCore.Actors.ActorRpcServer do
  require Logger
  alias HostCore.Actors.CallCounter
  use Gnat.Server

  def request(
        %{
          body: _body,
          reply_to: _reply_to,
          topic: topic
        } = msg
      ) do
    pk = topic |> String.split(".") |> Enum.at(-1)

    case Registry.lookup(Registry.ActorRegistry, pk) do
      [] ->
        {:error, "Actor #{pk} is not running on this host. RPC call skipped."}

      actors ->
        next_index = CallCounter.read_and_increment(pk)
        {pid, _value} = Enum.at(actors, rem(next_index, length(actors)))

        GenServer.cast(pid, {:handle_incoming_rpc, msg})
        :ok
    end
  end

  def error(
        %{gnat: gnat, reply_to: reply_to},
        error
      ) do
    Logger.error("Actor RPC handler failure: #{inspect(error)}")

    ir = %{
      msg: nil,
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

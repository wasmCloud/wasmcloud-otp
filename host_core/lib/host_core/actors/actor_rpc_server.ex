defmodule HostCore.Actors.ActorRpcServer do
  require Logger
  use Gnat.Server

  def request(
        %{
          body: _body,
          reply_to: _reply_to,
          topic: topic
        } = msg
      ) do
    pk = topic |> String.split(".") |> Enum.at(-1)

    # NOTE - dispatch doesn't invoke the handler if no registry entries exist for the given key

    # (This is a potentially blocking method. Need to spike to determine if this approach
    # is detrimental / causes locking)
    # Choose the least busy (smallest message queue length) actor in the registry
    # as the target for the inbound RPC
    #
    # Registry.dispatch(Registry.ActorRegistry, pk, fn entries ->
    #   {pid, _ql} =
    #     entries
    #     |> Enum.map(fn {pid, _value} ->
    #       {pid, Process.info(pid, :message_queue_len) |> elem(1)}
    #     end)
    #     |> Enum.sort(&(elem(&1, 1) <= elem(&2, 1)))
    #     |> Enum.at(0)

    #   GenServer.cast(pid, {:handle_incoming_rpc, msg})
    # end)

    Registry.dispatch(Registry.ActorRegistry, pk, fn entries ->
      {pid, _value} = entries |> Enum.random()
      GenServer.cast(pid, {:handle_incoming_rpc, msg})
    end)
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

defmodule HostCore.ControlInterface.Server do
  require Logger
  use Gnat.Server

  alias HostCore.ControlInterface.ACL

  def request(%{topic: topic, body: body, reply_to: reply_to}) do
    topic
    |> String.split(".")
    # wasmbus
    |> List.delete_at(0)
    # ctl
    |> List.delete_at(0)
    # prefix
    |> List.delete_at(0)
    |> List.to_tuple()
    |> handle_request(body, reply_to)

    :ok
  end

  defp handle_request({"get", "hosts"}, _body, reply_to) do
    IO.puts("HERE")
    {total, _} = :erlang.statistics(:wall_clock)

    res = %{
      id: HostCore.Host.host_key(),
      uptime: div(total, 1000)
    }

    Gnat.pub(:control_nats, reply_to, Jason.encode!(res))
  end

  defp handle_request({"get", host_id, "inv"}, _body, reply_to) do
    if host_id == HostCore.Host.host_key() do
      res = %{
        host_id: HostCore.Host.host_key(),
        labels: HostCore.Host.host_labels(),
        actors: ACL.all_actors(),
        providers: ACL.all_providers()
      }

      Gnat.pub(:control_nats, reply_to, Jason.encode!(res))
    end
  end

  defp handle_request(tuple, _body, _reply_to) do
    IO.puts("Got here #{tuple}")
  end
end

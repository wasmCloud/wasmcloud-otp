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
    |> IO.inspect()
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

  defp handle_request({"get", "claims"}, _body, reply_to) do
    raw_claims = :ets.tab2list(:claims_table)
    claims = raw_claims |> Enum.map(fn {_pk, %{} = claims} -> %{values: claims} end)

    res = %{
      claims: claims
    }

    Gnat.pub(:lattice_nats, reply_to, Jason.encode!(res))
  end

  defp handle_request({"get", "links"}, _body, reply_to) do
    raw_links = :ets.tab2list(:linkdef_table)

    links =
      raw_links
      |> Enum.map(fn {{pk, contract, link}, %{provider_key: provider_key, values: values}} ->
        %{
          actor_id: pk,
          provider_id: provider_key,
          link_name: link,
          contract_id: contract,
          values: values
        }
      end)

    res = %{
      links: links
    }

    Gnat.pub(:lattice_nats, reply_to, Jason.encode!(res))
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

  ### COMMANDS

  # Launch Actor
  # %{"actor_ref" => "wasmcloud.azurecr.io/echo:0.12.0", "host_id" => "Nxxxx"}

  defp handle_request({"cmd", host_id, "la"}, body, reply_to) do
    if host_id == HostCore.Host.host_key() do
      start_actor_command = Jason.decode!(body)

      case HostCore.Actors.ActorSupervisor.start_actor_from_oci(start_actor_command["actor_ref"]) do
        {:ok, _pid} ->
          ack = %{
            host_id: host_id,
            actor_ref: start_actor_command["actor_ref"]
          }

          Gnat.pub(:control_nats, reply_to, Jason.encode!(ack))

        {:error, e} ->
          Logger.error("Failed to start actor per remote call")

          ack = %{
            host_id: host_id,
            actor_ref: start_actor_command["actor_ref"],
            failure: "Failed to start actor: #{e}"
          }

          Gnat.pub(:control_nats, reply_to, Jason.encode!(ack))
      end
    end
  end

  # Stop Actor
  defp handle_request({"cmd", host_id, "sa"}, body, reply_to) do
    if host_id == HostCore.Host.host_key() do
      stop_actor_command = Jason.decode!(body)
      HostCore.Actors.ActorSupervisor.terminate_actor(stop_actor_command["actor_ref"], 1)
      ack = %{}
      Gnat.pub(:control_nats, reply_to, Jason.encode!(ack))
    end
  end

  # FALL THROUGH
  defp handle_request(tuple, _body, _reply_to) do
    IO.puts("Got here #{tuple}")
  end
end

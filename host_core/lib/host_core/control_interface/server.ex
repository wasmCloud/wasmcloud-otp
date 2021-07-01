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

  # Launch Provider
  defp handle_request({"cmd", host_id, "lp"}, body, reply_to) do
    if host_id == HostCore.Host.host_key() do
      start_provider_command = Jason.decode!(body)

      ack =
        case HostCore.Providers.ProviderSupervisor.start_executable_provider_from_oci(
               start_provider_command["provider_ref"],
               start_provider_command["link_name"]
             ) do
          {:ok, _pid} ->
            %{
              host_id: host_id,
              provider_ref: start_provider_command["provider_ref"]
            }

          {:error, e} ->
            %{
              host_id: host_id,
              provider_ref: start_provider_command["provider_ref"],
              error: "Failed to start provider: #{e}"
            }
        end

      IO.inspect(ack)
      Gnat.pub(:control_nats, reply_to, Jason.encode!(ack))
    end
  end

  # Stop Provider
  defp handle_request({"cmd", host_id, "sp"}, body, reply_to) do
    if host_id == HostCore.Host.host_key() do
      stop_provider_command = Jason.decode!(body)

      HostCore.Providers.ProviderSupervisor.terminate_provider(
        stop_provider_command["provider_ref"],
        stop_provider_command["link_name"]
      )

      Gnat.pub(:control_nats, reply_to, Jason.encode!(%{}))
    end
  end

  # Update Actor
  defp handle_request({"cmd", host_id, "upd"}, body, reply_to) do
    if host_id == HostCore.Host.host_key() do
      update_actor_command = Jason.decode!(body)

      # TODO - live updates for actors is not implemented yet
    end
  end

  # Auction Actor
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "actor"}, body, reply_to) do
    auction_request = Jason.decode!(body)
    host_labels = HostCore.Host.host_labels()
    required_labels = auction_request["constraints"]

    if Map.equal?(host_labels, Map.merge(host_labels, required_labels)) do
      ack = %{
        actor_ref: auction_request["actor_ref"],
        constraints: auction_request["constraints"],
        host_id: HostCore.Host.host_key()
      }

      Gnat.pub(:control_nats, reply_to, Jason.encode!(ack))
    end
  end

  # Auction Provider
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "provider"}, body, reply_to) do
    auction_request = Jason.decode!(body)
    host_labels = HostCore.Host.host_labels()
    required_labels = auction_request["constraints"]

    # TODO - don't answer this request if we're already running a provider
    # that matches this link_name and ref.
    if Map.equal?(host_labels, Map.merge(host_labels, required_labels)) do
      ack = %{
        provider_ref: auction_request["provider_ref"],
        link_name: auction_request["link_name"],
        constraints: auction_request["constraints"],
        host_id: HostCore.Host.host_key()
      }

      Gnat.pub(:control_nats, reply_to, Jason.encode!(ack))
    end
  end

  # FALL THROUGH
  defp handle_request(tuple, _body, _reply_to) do
    IO.puts("Got here #{tuple}")
  end
end

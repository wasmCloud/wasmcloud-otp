defmodule HostCore.ControlInterface.Server do
  @moduledoc false
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
  end

  ### PING
  # Answered by all hosts in a collect/gather operation by clients
  defp handle_request({"ping", "hosts"}, _body, _reply_to) do
    {total, _} = :erlang.statistics(:wall_clock)

    res = %{
      id: HostCore.Host.host_key(),
      uptime_seconds: div(total, 1000)
    }

    {:reply, Jason.encode!(res)}
  end

  ### GET queries
  # These are answered by one host per lattice (queue group subscription)

  # Retrieves claims from the in-memory cache
  defp handle_request({"get", "claims"}, _body, _reply_to) do
    claims = HostCore.Claims.Manager.get_claims()

    res = %{
      claims: claims
    }

    {:reply, Jason.encode!(res)}
  end

  # Retrieves link definitions from the in-memory cache
  defp handle_request({"get", "links"}, _body, _reply_to) do
    links = HostCore.Linkdefs.Manager.get_link_definitions()

    res = %{
      links: links
    }

    {:reply, Jason.encode!(res)}
  end

  # Retrieves the inventory of the current host
  defp handle_request({"get", host_id, "inv"}, _body, _reply_to) do
    if host_id == HostCore.Host.host_key() do
      res = %{
        host_id: HostCore.Host.host_key(),
        labels: HostCore.Host.host_labels(),
        actors: ACL.all_actors(),
        providers: ACL.all_providers()
      }

      {:reply, Jason.encode!(res)}
    else
      {:reply, failure_ack("Command received by incorrect host and could not be processed")}
    end
  end

  ### LINKDEFS
  # These requests are targeted at one host per lattice, changes made as a result
  # are emitted to the appropriate stream and cached

  # Put a link definition
  # This will first store the link definition in memory, then publish it to the stream
  # then publish it directly to the relevant provider via the RPC channel
  defp handle_request({"linkdefs", "put"}, body, _reply_to) do
    ld = Jason.decode!(body)

    HostCore.Linkdefs.Manager.put_link_definition(
      ld["actor_id"],
      ld["contract_id"],
      ld["link_name"],
      ld["provider_id"],
      ld["values"]
    )

    {:reply, success_ack()}
  end

  # Remove a link definition
  # This will first remove the link definition from memory, then publish the removal
  # message to the stream, then publish the removal directly to the relevant provider via the
  # RPC channel
  defp handle_request({"linkdefs", "del"}, body, _reply_to) do
    ld = Jason.decode!(body)

    HostCore.Linkdefs.Manager.del_link_definition(
      ld["actor_id"],
      ld["contract_id"],
      ld["link_name"]
    )

    {:reply, success_ack()}
  end

  ### COMMANDS
  # Commands are all targeted at a specific host and as such do not require
  # a queue group

  # Launch Actor
  # %{"actor_ref" => "wasmcloud.azurecr.io/echo:0.12.0", "host_id" => "Nxxxx"}
  defp handle_request({"cmd", _host_id, "la"}, body, _reply_to) do
    start_actor_command = Jason.decode!(body)

    case HostCore.Actors.ActorSupervisor.start_actor_from_oci(start_actor_command["actor_ref"]) do
      {:ok, _pid} ->
        {:reply, success_ack()}

      {:error, e} ->
        Logger.error("Failed to start actor per remote call")
        {:reply, failure_ack("Failed to start actor: #{e}")}
    end
  end

  # Stop Actor
  defp handle_request({"cmd", _host_id, "sa"}, body, _reply_to) do
    stop_actor_command = Jason.decode!(body)
    HostCore.Actors.ActorSupervisor.terminate_actor(stop_actor_command["actor_ref"], 1)
    {:reply, success_ack()}
  end

  # Scale Actor
  # input: #{"actor_id" => "...", "actor_ref" => "...", "replicas" => "..."}
  defp handle_request({"cmd", host_id, "scale"}, body, _reply_to) do
    scale_request = Jason.decode!(body)

    if host_id == HostCore.Host.host_key() do
      actor_id = scale_request["actor_id"]
      actor_ref = scale_request["actor_ref"]
      replicas = String.to_integer(scale_request["replicas"])

      case HostCore.Actors.ActorSupervisor.scale_actor(actor_id, replicas, actor_ref) do
        :ok ->
          {:reply, success_ack()}

        {:error, err} ->
          {:reply, failure_ack("Error scaling actor: #{err}")}
      end
    else
      {:reply, failure_ack("Command received by incorrect host and could not be processed")}
    end
  end

  # Launch Provider
  defp handle_request({"cmd", _host_id, "lp"}, body, _reply_to) do
    start_provider_command = Jason.decode!(body)

    ack =
      case HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
             start_provider_command["provider_ref"],
             start_provider_command["link_name"]
           ) do
        {:ok, _pid} ->
          success_ack()

        {:error, e} ->
          failure_ack("Failed to start provider: #{e}")
      end

    {:reply, ack}
  end

  # Stop Provider
  defp handle_request({"cmd", _host_id, "sp"}, body, _reply_to) do
    stop_provider_command = Jason.decode!(body)

    HostCore.Providers.ProviderSupervisor.terminate_provider(
      stop_provider_command["provider_ref"],
      stop_provider_command["link_name"]
    )

    {:reply, success_ack()}
  end

  # Update Actor
  # input: %{"new_actor_ref" => "... oci URL ..."} , public key, etc needs to match a running actor
  defp handle_request({"cmd", _host_id, "upd"}, body, _reply_to) do
    update_actor_command = Jason.decode!(body)

    response =
      case HostCore.Actors.ActorSupervisor.live_update(update_actor_command["new_actor_ref"]) do
        :ok -> success_ack()
        {:error, err} -> failure_ack("Unable to perform live update: #{err}")
      end

    {:reply, response}
  end

  ### AUCTIONS
  # All auctions are sent to every host within the lattice
  # so no queue subscription is used.

  # Auction Actor
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "actor"}, body, _reply_to) do
    auction_request = Jason.decode!(body)
    host_labels = HostCore.Host.host_labels()
    required_labels = auction_request["constraints"]

    if Map.equal?(host_labels, Map.merge(host_labels, required_labels)) do
      ack = %{
        actor_ref: auction_request["actor_ref"],
        constraints: auction_request["constraints"],
        host_id: HostCore.Host.host_key()
      }

      {:reply, Jason.encode!(ack)}
    else
      # We don't respond to an auction request if this host cannot satisfy the constraints
      :ok
    end
  end

  # Auction Provider
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "provider"}, body, _reply_to) do
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

      {:reply, Jason.encode!(ack)}
    else
      # We don't respond to an auction request if this host cannot satisfy the constraints
      :ok
    end
  end

  # FALL THROUGH
  defp handle_request(tuple, _body, _reply_to) do
    Logger.warn("Unexpected/unhandled lattice control command: #{tuple}")
  end

  defp success_ack() do
    Jason.encode!(%{
      accepted: true,
      error: ""
    })
  end

  defp failure_ack(error) do
    Jason.encode!(%{
      accepted: false,
      error: error
    })
  end
end

defmodule HostCore.ControlInterface.Server do
  @moduledoc false
  require Logger
  use Gnat.Server

  alias HostCore.ControlInterface.ACL
  alias HostCore.CloudEvent

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
    with {:ok, ld} <- Jason.decode(body),
         true <-
           ["actor_id", "contract_id", "link_name", "provider_id", "values"]
           |> Enum.all?(&Map.has_key?(ld, &1)) do
      HostCore.Linkdefs.Manager.put_link_definition(
        ld["actor_id"],
        ld["contract_id"],
        ld["link_name"],
        ld["provider_id"],
        ld["values"]
      )

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Invalid link definition put request")}
    end
  end

  # Remove a link definition
  # This will first remove the link definition from memory, then publish the removal
  # message to the stream, then publish the removal directly to the relevant provider via the
  # RPC channel
  defp handle_request({"linkdefs", "del"}, body, _reply_to) do
    with {:ok, ld} <- Jason.decode(body),
         true <-
           ["actor_id", "contract_id", "link_name"]
           |> Enum.all?(&Map.has_key?(ld, &1)) do
      HostCore.Linkdefs.Manager.del_link_definition(
        ld["actor_id"],
        ld["contract_id"],
        ld["link_name"]
      )

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Invalid link definition removal request")}
    end
  end

  ### COMMANDS
  # Commands are all targeted at a specific host and as such do not require
  # a queue group

  # Launch Actor
  # %{"actor_ref" => "wasmcloud.azurecr.io/echo:0.12.0", "host_id" => "Nxxxx"}
  defp handle_request({"cmd", _host_id, "la"}, body, _reply_to) do
    with {:ok, start_actor_command} <- Jason.decode(body),
         true <-
           Map.has_key?(start_actor_command, "actor_ref") do
      Task.start(fn ->
        case HostCore.Actors.ActorSupervisor.start_actor_from_oci(
               start_actor_command["actor_ref"]
             ) do
          {:ok, _pid} ->
            Logger.debug("Completed request to start actor #{start_actor_command["actor_ref"]}")

          {:error, e} ->
            Logger.error(
              "Failed to start actor #{start_actor_command["actor_ref"]} per remote call"
            )

            publish_actor_start_failed(start_actor_command["actor_ref"], inspect(e))
        end
      end)

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Invalid launch actor JSON request")}
    end
  end

  # Stop Actor
  defp handle_request({"cmd", _host_id, "sa"}, body, _reply_to) do
    with {:ok, stop_actor_command} <- Jason.decode(body),
         true <-
           ["actor_ref", "count"]
           |> Enum.all?(&Map.has_key?(stop_actor_command, &1)) do
      HostCore.Actors.ActorSupervisor.terminate_actor(
        stop_actor_command["actor_ref"],
        stop_actor_command["count"]
      )

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Invalid request to stop actor")}
    end
  end

  # Scale Actor
  # input: #{"actor_id" => "...", "actor_ref" => "...", "replicas" => "..."}
  defp handle_request({"cmd", host_id, "scale"}, body, _reply_to) do
    with {:ok, scale_request} <- Jason.decode(body),
         true <-
           ["actor_id", "actor_ref", "replicas"]
           |> Enum.all?(&Map.has_key?(scale_request, &1)) do
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
    else
      _ ->
        {:reply, failure_ack("Invalid scale actor JSON request")}
    end
  end

  # Launch Provider
  defp handle_request({"cmd", _host_id, "lp"}, body, _reply_to) do
    with {:ok, start_provider_command} <- Jason.decode(body),
         true <-
           ["provider_ref", "link_name"]
           |> Enum.all?(&Map.has_key?(start_provider_command, &1)) do
      Task.start(fn ->
        case HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
               start_provider_command["provider_ref"],
               start_provider_command["link_name"],
               Map.get(start_provider_command, "configuration", "")
             ) do
          {:ok, _pid} ->
            Logger.debug("Completed request to start provider")

          {:error, e} ->
            publish_provider_start_failed(start_provider_command, inspect(e))
        end
      end)

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Improperly formed start provider command JSON")}
    end
  end

  # Stop Provider
  defp handle_request({"cmd", _host_id, "sp"}, body, _reply_to) do
    with {:ok, stop_provider_command} <- Jason.decode(body),
         true <-
           ["provider_ref", "link_name"]
           |> Enum.all?(&Map.has_key?(stop_provider_command, &1)) do
      HostCore.Providers.ProviderSupervisor.terminate_provider(
        stop_provider_command["provider_ref"],
        stop_provider_command["link_name"]
      )

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Invalid JSON request for stop provider")}
    end
  end

  # Update Actor
  # input: %{"new_actor_ref" => "... oci URL ..."} , public key, etc needs to match a running actor
  defp handle_request({"cmd", _host_id, "upd"}, body, _reply_to) do
    with {:ok, update_actor_command} = Jason.decode(body),
         true <- Map.has_key?(update_actor_command, "new_actor_ref") do
      response =
        case HostCore.Actors.ActorSupervisor.live_update(update_actor_command["new_actor_ref"]) do
          :ok -> success_ack()
          {:error, err} -> failure_ack("Unable to perform live update: #{err}")
        end

      {:reply, response}
    else
      _ ->
        {:reply, failure_ack("Invalid JSON request to update actor")}
    end
  end

  # Stop Host
  defp handle_request({"cmd", host_id, "stop"}, body, _reply_to) do
    case Jason.decode(body) do
      # TODO: Right now this will contain a parameter for timeout. Obviously how this works currently
      # only results in the graceful shutdowns built into the system. There may be some inflight work
      # we want to wait for up to the timeout. We could use this library possibly so we can put in
      # hooks: https://github.com/botsquad/graceful_stop.
      {:ok, stop_host_command} ->
        if host_id == HostCore.Host.host_key() do
          Logger.info("Received stop request for host")
          Process.send_after(HostCore.Host, {:do_stop, stop_host_command["timeout"]}, 100)
          {:reply, success_ack()}
        else
          {:reply, failure_ack("Handled stop request for incorrect host. Ignoring")}
        end

      {:error, e} ->
        Logger.error("Unable to parse incoming stop request: #{e}")
        {:reply, failure_ack("Unable to parse stop host command: #{e}")}
    end
  end

  ### AUCTIONS
  # All auctions are sent to every host within the lattice
  # so no queue subscription is used.

  # Auction Actor
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "actor"}, body, _reply_to) do
    with {:ok, auction_request} <- Jason.decode(body),
         true <-
           ["constraints", "actor_ref"]
           |> Enum.all?(&Map.has_key?(auction_request, &1)) do
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
    else
      _ ->
        {:reply, failure_ack("Invalid JSON request for actor auction")}
    end
  end

  # Auction Provider
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "provider"}, body, _reply_to) do
    with {:ok, auction_request} <- Jason.decode(body),
         true <-
           ["constraints", "provider_ref"]
           |> Enum.all?(&Map.has_key?(auction_request, &1)) do
      host_labels = HostCore.Host.host_labels()
      required_labels = auction_request["constraints"]

      # TODO - don't answer this request if we're already running a provider
      # that matches this link_name and ref.
      if Map.equal?(host_labels, Map.merge(host_labels, required_labels)) do
        ack = %{
          provider_ref: auction_request["provider_ref"],
          link_name: Map.get(auction_request, "link_name", "default"),
          constraints: auction_request["constraints"],
          host_id: HostCore.Host.host_key()
        }

        {:reply, Jason.encode!(ack)}
      else
        # We don't respond to an auction request if this host cannot satisfy the constraints
        :ok
      end
    else
      _ ->
        {:reply, failure_ack("Invalid JSON request to auction provider")}
    end
  end

  # FALL THROUGH
  defp handle_request(tuple, _body, _reply_to) do
    Logger.warn("Unexpected/unhandled lattice control command: #{tuple}")
  end

  defp publish_actor_start_failed(actor_ref, msg) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        actor_ref: actor_ref,
        error: msg
      }
      |> CloudEvent.new("actor_start_failed")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  defp publish_provider_start_failed(command, msg) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        provider_ref: command["provider_ref"],
        link_name: command["link_name"],
        error: msg
      }
      |> CloudEvent.new("provider_start_failed")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
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

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
  end

  defp handle_request({"get", "hosts"}, _body, _reply_to) do
    {total, _} = :erlang.statistics(:wall_clock)

    res = %{
      id: HostCore.Host.host_key(),
      uptime: div(total, 1000)
    }

    {:reply, Jason.encode!(res)}
  end

  defp handle_request({"get", "claims"}, _body, _reply_to) do
    claims = HostCore.Claims.Server.get_claims()

    res = %{
      claims: claims
    }

    {:reply, Jason.encode!(res)}
  end

  defp handle_request({"get", "links"}, _body, _reply_to) do
    links = HostCore.Linkdefs.Server.get_link_definitions()

    res = %{
      links: links
    }

    {:reply, Jason.encode!(res)}
  end

  defp handle_request({"get", host_id, "inv"}, _body, _reply_to) do
    if host_id == HostCore.Host.host_key() do
      res = %{
        host_id: HostCore.Host.host_key(),
        labels: HostCore.Host.host_labels(),
        actors: ACL.all_actors(),
        providers: ACL.all_providers()
      }

      {:reply, Jason.encode!(res)}
    end

    # TODO: reply with error or something for wrong host id
  end

  ### COMMANDS

  # Launch Actor
  # %{"actor_ref" => "wasmcloud.azurecr.io/echo:0.12.0", "host_id" => "Nxxxx"}

  defp handle_request({"cmd", host_id, "la"}, body, _reply_to) do
    if host_id == HostCore.Host.host_key() do
      start_actor_command = Jason.decode!(body)

      case HostCore.Actors.ActorSupervisor.start_actor_from_oci(start_actor_command["actor_ref"]) do
        {:ok, _pid} ->
          ack = %{
            host_id: host_id,
            actor_ref: start_actor_command["actor_ref"]
          }

          {:reply, Jason.encode!(ack)}

        {:error, e} ->
          Logger.error("Failed to start actor per remote call")

          ack = %{
            host_id: host_id,
            actor_ref: start_actor_command["actor_ref"],
            failure: "Failed to start actor: #{e}"
          }

          {:reply, Jason.encode!(ack)}
      end

      # TODO: reply with error or something for wrong host id
    end
  end

  # Stop Actor
  defp handle_request({"cmd", host_id, "sa"}, body, reply_to) do
    if host_id == HostCore.Host.host_key() do
      stop_actor_command = Jason.decode!(body)
      HostCore.Actors.ActorSupervisor.terminate_actor(stop_actor_command["actor_ref"], 1)
      ack = %{}
      {:reply, Jason.encode!(ack)}
    end

    # TODO: reply with error or something for wrong host id
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

      {:reply, Jason.encode!(ack)}
    end

    # TODO: handle wrong host ID
  end

  # Stop Provider
  defp handle_request({"cmd", host_id, "sp"}, body, _reply_to) do
    if host_id == HostCore.Host.host_key() do
      stop_provider_command = Jason.decode!(body)

      HostCore.Providers.ProviderSupervisor.terminate_provider(
        stop_provider_command["provider_ref"],
        stop_provider_command["link_name"]
      )

      {:reply, Jason.encode!(%{})}
    end

    # TODO: handle wrong host ID
  end

  # Update Actor
  defp handle_request({"cmd", host_id, "upd"}, body, _reply_to) do
    if host_id == HostCore.Host.host_key() do
      update_actor_command = Jason.decode!(body)

      # TODO - live updates for actors is not implemented yet
    end
  end

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
    end

    # TODO: handle no match host labels
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
    end

    # TODO: don't answer or return error or somethign
  end

  # FALL THROUGH
  defp handle_request(tuple, _body, _reply_to) do
    Logger.warn("Unexpected/unhandled lattice control command: #{tuple}")
  end
end

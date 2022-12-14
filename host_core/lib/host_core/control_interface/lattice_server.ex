defmodule HostCore.ControlInterface.LatticeServer do
  @moduledoc false
  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  use Gnat.Server

  alias HostCore.CloudEvent
  alias HostCore.Linkdefs.Manager, as: LinkdefsManager

  import HostCore.Nats,
    only: [safe_pub: 3, control_connection: 1]

  def request(%{topic: topic, body: body, reply_to: reply_to} = req) do
    req
    |> Map.get(:headers)
    |> reconstitute_trace_context()

    Logger.debug("Received control interface request on #{topic}")

    case String.split(topic, ".", parts: 4) do
      [_wasmbus, _ctl, prefix, remainder] ->
        remainder
        |> String.split(".")
        |> List.to_tuple()
        |> handle_request(body, reply_to, prefix)

      _ ->
        {:reply, failure_ack("Invalid request topic")}
    end
  end

  def reconstitute_trace_context(headers) when is_list(headers) do
    if Enum.any?(headers, fn {k, _v} -> k == "traceparent" end) do
      :otel_propagator_text_map.extract(headers)
    else
      OpenTelemetry.Ctx.clear()
    end
  end

  def reconstitute_trace_context(_) do
    # If there is a nil for the headers, then clear context
    OpenTelemetry.Ctx.clear()
  end

  ### PING
  # Answered by all hosts in a collect/gather operation by clients
  defp handle_request({"ping", "hosts"}, _body, reply_to, prefix) do
    Tracer.with_span "Handle Host Ping (ctl)", kind: :server do
      Tracer.set_attribute("lattice_id", prefix)

      for pid <- HostCore.Lattice.LatticeSupervisor.host_pids_in_lattice(prefix),
          pingres = HostCore.Vhost.VirtualHost.generate_ping_reply(pid) do
        safe_pub(control_connection(prefix), reply_to, Jason.encode!(pingres))
        HostCore.Vhost.VirtualHost.emit_heartbeat(pid)
      end

      :ok
    end
  end

  ### GET queries
  # These are answered by one host per lattice (queue group subscription)

  # Retrieves claims from the in-memory cache
  defp handle_request({"get", "claims"}, _body, _reply_to, prefix) do
    Tracer.with_span "Handle Claims Request (ctl)", kind: :server do
      claims = HostCore.Claims.Manager.get_claims(prefix)

      res = %{
        claims: claims
      }

      {:reply, Jason.encode!(res)}
    end
  end

  # Retrieves link definitions from the in-memory cache
  defp handle_request({"get", "links"}, _body, _reply_to, prefix) do
    Tracer.with_span "Handle Linkdef Request (ctl)", kind: :server do
      links = HostCore.Linkdefs.Manager.get_link_definitions(prefix)

      res = %{
        links: links
      }

      {:reply, Jason.encode!(res)}
    end
  end

  ### LINKDEFS
  # These requests are targeted at one host per lattice, changes made as a result
  # are emitted to the appropriate stream and cached.
  # THESE ARE NOW DEPRECATED
  # Eventually the host will stop subscribing to these topics

  defp handle_request({"linkdefs", "put"}, body, _reply_to, prefix) do
    Tracer.with_span "Handle Linkdef Put (ctl)", kind: :server do
      with {:ok, ld} <- Jason.decode(body),
           true <- has_values(ld, ["actor_id", "contract_id", "link_name", "provider_id"]) do
        HostCore.Linkdefs.Manager.put_link_definition(
          prefix,
          ld["actor_id"],
          ld["contract_id"],
          ld["link_name"],
          ld["provider_id"],
          ld["values"] || %{}
        )

        {:reply, success_ack()}
      else
        _ ->
          {:reply, failure_ack("Invalid link definition put request")}
      end
    end
  end

  defp handle_request({"linkdefs", "del"}, body, _reply_to, prefix) do
    Tracer.with_span "Handle Linkdef Del (ctl)", kind: :server do
      with {:ok, ld} <- Jason.decode(body),
           true <- has_values(ld, ["actor_id", "contract_id", "link_name"]) do
        HostCore.Linkdefs.Manager.del_link_definition_by_triple(
          prefix,
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
  end

  ### COMMANDS
  # Commands are all targeted at a specific host and as such do not require
  # a queue group

  ### REGISTRY CREDENTIALS (via Config Service)
  # note that every host in a lattice receives these credentials, so we ask the
  # lattice supervisor for a list of hosts to receive the registry credentials update
  defp handle_request({"registries", "put"}, body, _reply_to, prefix) do
    Tracer.with_span "Handle Registries Put (ctl)", kind: :server do
      with {:ok, credsmap} <- Jason.decode(body) do
        targets = HostCore.Lattice.LatticeSupervisor.host_pids_in_lattice(prefix)

        targets
        |> Enum.each(fn pid -> HostCore.Vhost.VirtualHost.set_credsmap(pid, credsmap) end)

        Logger.debug(
          "Replaced registry credential map, new registry count: #{length(Map.keys(credsmap))}"
        )

        {:reply, success_ack()}
      else
        _ ->
          Logger.error("Failed to update registry credential map")
          {:reply, failure_ack("Failed to update registry credential map")}
      end
    end
  end

  ### AUCTIONS
  # All auctions are sent to every host within the lattice
  # so no queue subscription is used.

  # Auction Actor
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "actor"}, body, reply_to, prefix) do
    Tracer.with_span "Handle Actor Auction Request (ctl)", kind: :server do
      with {:ok, auction_request} <- Jason.decode(body),
           true <- has_values(auction_request, ["actor_ref"]) do
        for {host_id, pid} <- HostCore.Lattice.LatticeSupervisor.hosts_in_lattice(prefix),
            labels = HostCore.Vhost.VirtualHost.labels(pid) do
          required_labels = auction_request["constraints"] || %{}

          if Map.equal?(labels, Map.merge(labels, required_labels)) do
            ack = %{
              actor_ref: auction_request["actor_ref"],
              constraints: required_labels,
              host_id: host_id
            }

            safe_pub(control_connection(prefix), reply_to, Jason.encode!(ack))
          end
        end

        :ok
      else
        _ ->
          {:reply, failure_ack("Invalid JSON request for actor auction")}
      end
    end
  end

  # Auction Provider
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "provider"}, body, reply_to, prefix) do
    Tracer.with_span "Handle Provider Auction Request (ctl)", kind: :server do
      with {:ok, auction_request} <- Jason.decode(body),
           true <- has_values(auction_request, ["provider_ref"]) do
        for {host_id, pid} <- HostCore.Lattice.LatticeSupervisor.hosts_in_lattice(prefix),
            host_labels = HostCore.Vhost.VirtualHost.labels(pid) do
          required_labels = auction_request["constraints"] || %{}
          provider_ref = auction_request["provider_ref"]
          link_name = Map.get(auction_request, "link_name", "default")

          if Map.equal?(host_labels, Map.merge(host_labels, required_labels)) &&
               !HostCore.Providers.ProviderSupervisor.provider_running?(
                 host_id,
                 provider_ref,
                 link_name,
                 ""
               ) do
            ack = %{
              provider_ref: provider_ref,
              link_name: link_name,
              constraints: required_labels,
              host_id: host_id
            }

            safe_pub(control_connection(prefix), reply_to, Jason.encode!(ack))
          end
        end

        :ok
      else
        _ ->
          {:reply, failure_ack("Invalid JSON request to auction provider")}
      end
    end
  end

  # FALL THROUGH
  defp handle_request(tuple, _body, _reply_to, _prefix) do
    Tracer.with_span "Handle Unexpected Control Command (ctl)", kind: :server do
      Logger.warn("Unexpected/unhandled lattice control command: #{inspect(tuple)}")
      Tracer.set_status(:error, "Unexpected control command: #{inspect(tuple)}")
    end
  end

  @spec publish_actor_start_failed(
          host :: String.t(),
          lattice_prefix :: String.t(),
          actor_ref :: String.t(),
          msg :: String.t()
        ) :: :ok
  def publish_actor_start_failed(host, lattice_prefix, actor_ref, msg) do
    msg =
      %{
        actor_ref: actor_ref,
        error: msg
      }
      |> CloudEvent.new("actor_start_failed", host)

    topic = "wasmbus.evt.#{lattice_prefix}"

    HostCore.Nats.safe_pub(HostCore.Nats.control_connection(lattice_prefix), topic, msg)
  end

  def success_ack() do
    Jason.encode!(%{
      accepted: true,
      error: ""
    })
  end

  def failure_ack(error) do
    Jason.encode!(%{
      accepted: false,
      error: error
    })
  end

  # returns true if all keys have non-nil values in the map
  def has_values(m, keys) when is_map(m) and is_list(keys) do
    Enum.all?(keys, &Map.get(m, &1))
  end

  def has_values(_m, _keys), do: false
end

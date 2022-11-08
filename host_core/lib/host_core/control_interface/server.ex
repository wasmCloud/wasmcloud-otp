defmodule HostCore.ControlInterface.Server do
  @moduledoc false
  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  use Gnat.Server

  alias HostCore.ControlInterface.ACL
  alias HostCore.CloudEvent

  import HostCore.Actors.ActorSupervisor,
    only: [start_actor_from_bindle: 3, start_actor_from_oci: 3, start_actor_from_localstore: 3]

  import HostCore.Providers.ProviderSupervisor,
    only: [start_provider_from_bindle: 4, start_provider_from_oci: 4]

  def request(%{topic: topic, body: body, reply_to: reply_to} = req) do
    headers = Map.get(req, :headers)
    reconstitute_trace_context(headers)

    Logger.debug("Received control interface request on #{topic}")

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

  defp reconstitute_trace_context(headers) when is_list(headers) do
    if Enum.any?(headers, fn {k, _v} -> k == "traceparent" end) do
      :otel_propagator_text_map.extract(headers)
    else
      OpenTelemetry.Ctx.clear()
    end
  end

  defp reconstitute_trace_context(_) do
    # If there is a nil for the headers, then clear context
    OpenTelemetry.Ctx.clear()
  end

  ### PING
  # Answered by all hosts in a collect/gather operation by clients
  defp handle_request({"ping", "hosts"}, _body, _reply_to) do
    Tracer.with_span "Handle Host Ping (ctl)", kind: :server do
      {total, _} = :erlang.statistics(:wall_clock)

      ut_seconds = div(total, 1000)

      ut_human =
        ut_seconds
        |> Timex.Duration.from_seconds()
        |> Timex.Format.Duration.Formatters.Humanized.format()

      {js_domain, ctl_host, prov_rpc_host, rpc_host, lattice_prefix, cluster_key} =
        case :ets.lookup(:config_table, :config) do
          [config: config_map] ->
            {config_map.js_domain, config_map.ctl_host, config_map.prov_rpc_host,
             config_map.rpc_host, config_map.lattice_prefix, config_map.cluster_key}

          _ ->
            # We would only ever hit this branch if something is horribly wrong with ETS and our
            # startup routine
            {nil, "localhost", "localhost", "localhost", "config-failure", ""}
        end

      res = %{
        id: HostCore.Host.host_key(),
        issuer: cluster_key,
        labels: HostCore.Host.host_labels(),
        friendly_name: HostCore.Host.friendly_name(),
        uptime_seconds: ut_seconds,
        uptime_human: ut_human,
        version: Application.spec(:host_core, :vsn) |> to_string(),
        cluster_issuers: HostCore.Host.cluster_issuers() |> Enum.join(","),
        js_domain: js_domain,
        ctl_host: ctl_host,
        prov_rpc_host: prov_rpc_host,
        rpc_host: rpc_host,
        lattice_prefix: lattice_prefix
      }

      HostCore.HeartbeatEmitter.emit_heartbeat()

      {:reply, Jason.encode!(res)}
    end
  end

  ### GET queries
  # These are answered by one host per lattice (queue group subscription)

  # Retrieves claims from the in-memory cache
  defp handle_request({"get", "claims"}, _body, _reply_to) do
    Tracer.with_span "Handle Claims Request (ctl)", kind: :server do
      claims = HostCore.Claims.Manager.get_claims()

      res = %{
        claims: claims
      }

      {:reply, Jason.encode!(res)}
    end
  end

  # Retrieves link definitions from the in-memory cache
  defp handle_request({"get", "links"}, _body, _reply_to) do
    Tracer.with_span "Handle Linkdef Request (ctl)", kind: :server do
      links = HostCore.Linkdefs.Manager.get_link_definitions()

      res = %{
        links: links
      }

      {:reply, Jason.encode!(res)}
    end
  end

  # Retrieves the inventory of the current host
  defp handle_request({"get", host_id, "inv"}, _body, _reply_to) do
    Tracer.with_span "Handle Inventory Request (ctl)", kind: :server do
      {host_key, cluster_key} =
        case :ets.lookup(:config_table, :config) do
          [config: config_map] ->
            {config_map.host_key, config_map.cluster_key}

          _ ->
            # We would only ever hit this branch if something is horribly wrong with ETS and our
            # startup routine
            {"none", "none", []}
        end

      if host_id == HostCore.Host.host_key() do
        res = %{
          host_id: host_key,
          issuer: cluster_key,
          labels: HostCore.Host.host_labels(),
          friendly_name: HostCore.Host.friendly_name(),
          actors: ACL.all_actors(),
          providers: ACL.all_providers()
        }

        {:reply, Jason.encode!(res)}
      else
        {:reply, failure_ack("Command received by incorrect host and could not be processed")}
      end
    end
  end

  ### LINKDEFS
  # These requests are targeted at one host per lattice, changes made as a result
  # are emitted to the appropriate stream and cached

  # Put a link definition
  # This will first store the link definition in memory, then publish it to the stream
  # then publish it directly to the relevant provider via the RPC channel
  defp handle_request({"linkdefs", "put"}, body, _reply_to) do
    Tracer.with_span "Handle Linkdef Put (ctl)", kind: :server do
      with {:ok, ld} <- Jason.decode(body),
           true <- has_values(ld, ["actor_id", "contract_id", "link_name", "provider_id"]) do
        HostCore.Linkdefs.Manager.put_link_definition(
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

  # Remove a link definition
  # This will first remove the link definition from memory, then publish the removal
  # message to the stream, then publish the removal directly to the relevant provider via the
  # RPC channel
  defp handle_request({"linkdefs", "del"}, body, _reply_to) do
    Tracer.with_span "Handle Linkdef Del (ctl)", kind: :server do
      with {:ok, ld} <- Jason.decode(body),
           true <- has_values(ld, ["actor_id", "contract_id", "link_name"]) do
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
  end

  ### COMMANDS
  # Commands are all targeted at a specific host and as such do not require
  # a queue group

  # Launch Actor
  # %{"actor_ref" => "wasmcloud.azurecr.io/echo:0.12.0", "host_id" => "Nxxxx", "count" => 3}
  # %{"actor_ref" => "bindle://example.com/echo/0.12.0", "host_id" => "Nxxxx", "count" => 4}
  defp handle_request({"cmd", _host_id, "la"}, body, _reply_to) do
    with {:ok, start_actor_command} <- Jason.decode(body),
         actor_ref <- Map.get(start_actor_command, "actor_ref"),
         true <- actor_ref != nil do
      ctx = Tracer.current_span_ctx()

      Task.start(fn ->
        Tracer.set_current_span(ctx)

        Tracer.with_span "Handle Launch Actor Request (ctl)", kind: :server do
          count = Map.get(start_actor_command, "count", 1)
          annotations = Map.get(start_actor_command, "annotations") || %{}

          Tracer.set_attribute("count", count)

          res =
            case actor_ref do
              "bindle://" <> _rest ->
                start_actor_from_bindle(actor_ref, count, annotations)

              "lattice://" <> pk ->
                start_actor_from_localstore(pk, count, annotations)

              _ ->
                # assume default is OCI
                start_actor_from_oci(actor_ref, count, annotations)
            end

          case res do
            {:ok, _pid} ->
              Logger.debug("Completed request to start actor #{actor_ref}",
                actor_ref: actor_ref
              )

              Tracer.set_status(:ok, "")

            {:error, e} ->
              Logger.error(
                "Failed to start actor #{actor_ref}, #{inspect(e)}",
                actor_ref: actor_ref
              )

              Tracer.set_status(:error, "Failed to start actor")

              publish_actor_start_failed(actor_ref, inspect(e))
          end
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
    Tracer.with_span "Handle Stop Actor Request (ctl)", kind: :server do
      with {:ok, stop_actor_command} <- Jason.decode(body),
           true <- has_values(stop_actor_command, ["actor_ref", "count"]) do
        HostCore.Actors.ActorSupervisor.terminate_actor(
          stop_actor_command["actor_ref"],
          stop_actor_command["count"],
          Map.get(stop_actor_command, "annotations") || %{}
        )

        {:reply, success_ack()}
      else
        _ ->
          {:reply, failure_ack("Invalid request to stop actor")}
      end
    end
  end

  # Scale Actor
  # input: #{"actor_id" => "...", "actor_ref" => "...", "count" => 5}
  defp handle_request({"cmd", host_id, "scale"}, body, _reply_to) do
    with {:ok, scale_request} <- Jason.decode(body),
         true <- has_values(scale_request, ["actor_id", "actor_ref", "count"]) do
      if host_id == HostCore.Host.host_key() do
        actor_id = scale_request["actor_id"]
        actor_ref = scale_request["actor_ref"]
        count = scale_request["count"]

        ctx = Tracer.current_span_ctx()

        Task.start(fn ->
          Tracer.set_current_span(ctx)

          Tracer.with_span "Handle Scale Actor Request (ctl)", kind: :server do
            case HostCore.Actors.ActorSupervisor.scale_actor(actor_id, count, actor_ref) do
              {:error, err} ->
                Logger.error("Error scaling actor #{actor_id}: #{err}", actor_id: actor_id)

              _ ->
                :ok
            end
          end
        end)

        {:reply, success_ack()}
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
         true <- has_values(start_provider_command, ["provider_ref", "link_name"]) do
      if !HostCore.Providers.ProviderSupervisor.provider_running?(
           start_provider_command["provider_ref"],
           start_provider_command["link_name"]
         ) do
        ctx = Tracer.current_span_ctx()

        Task.start(fn ->
          Tracer.set_current_span(ctx)

          Tracer.with_span "Handle Launch Provider Request (ctl)", kind: :server do
            annotations = Map.get(start_provider_command, "annotations") || %{}

            res =
              if String.starts_with?(start_provider_command["provider_ref"], "bindle://") do
                start_provider_from_bindle(
                  start_provider_command["provider_ref"],
                  start_provider_command["link_name"],
                  Map.get(start_provider_command, "configuration", ""),
                  annotations
                )
              else
                start_provider_from_oci(
                  start_provider_command["provider_ref"],
                  start_provider_command["link_name"],
                  Map.get(start_provider_command, "configuration", ""),
                  annotations
                )
              end

            case res do
              {:ok, _pid} ->
                Logger.debug(
                  "Successfully started provider #{start_provider_command["provider_ref"]} (#{start_provider_command["link_name"]})"
                )

              {:error, e} ->
                Tracer.set_status(:error, inspect(e))

                Logger.error(
                  "Failed to start provider #{start_provider_command["provider_ref"]} (#{start_provider_command["link_name"]}: #{inspect(e)}"
                )

                publish_provider_start_failed(start_provider_command, inspect(e))
            end
          end
        end)

        {:reply, success_ack()}
      else
        warning =
          "Ignoring request to start provider, #{start_provider_command["provider_ref"]} (#{start_provider_command["link_name"]}) is already running"

        Logger.warn(warning)

        publish_provider_start_failed(start_provider_command, warning)
        {:reply, failure_ack("Provider with that link name is already running on this host")}
      end
    else
      _ ->
        {:reply, failure_ack("Improperly formed start provider command JSON")}
    end
  end

  # Stop Provider
  defp handle_request({"cmd", _host_id, "sp"}, body, _reply_to) do
    Tracer.with_span "Handle Stop Provider Request (ctl)", kind: :server do
      with {:ok, stop_provider_command} <- Jason.decode(body),
           true <- has_values(stop_provider_command, ["provider_ref", "link_name"]) do
        Tracer.set_attribute("provider_ref", stop_provider_command["provider_ref"])
        Tracer.set_attribute("link_name", stop_provider_command["link_name"])

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
  end

  # Update Actor
  # input: %{"new_actor_ref" => "... oci URL ..."} , public key, etc needs to match a running actor
  defp handle_request({"cmd", _host_id, "upd"}, body, _reply_to) do
    Tracer.with_span "Handle Live Update Request (ctl)", kind: :server do
      with {:ok, update_actor_command} = Jason.decode(body),
           true <- has_values(update_actor_command, ["new_actor_ref"]) do
        # Note to the curious - we can update existing actors using nothing but the new ref (e.g. we don't need the old)
        # because a precondition is that the new ref must have the same public key as the running actor
        Tracer.set_attribute("new_actor_ref", update_actor_command["new_actor_ref"])
        span_ctx = Tracer.current_span_ctx()

        response =
          case HostCore.Actors.ActorSupervisor.live_update(
                 update_actor_command["new_actor_ref"],
                 span_ctx
               ) do
            :ok ->
              success_ack()

            {:error, err} ->
              Tracer.set_status(:error, "#{err}")
              failure_ack("Unable to perform live update: #{err}")
          end

        {:reply, response}
      else
        _ ->
          Tracer.set_status(:error, "Invalid JSON request")
          {:reply, failure_ack("Invalid JSON request to update actor")}
      end
    end
  end

  # Stop Host
  defp handle_request({"cmd", host_id, "stop"}, body, _reply_to) do
    Tracer.with_span "Handle Stop Host Command (ctl)", kind: :server do
      case Jason.decode(body) do
        # TODO: Right now this will contain a parameter for timeout. Obviously how this works currently
        # only results in the graceful shutdowns built into the system. There may be some inflight work
        # we want to wait for up to the timeout. We could use this library possibly so we can put in
        # hooks: https://github.com/botsquad/graceful_stop.
        {:ok, stop_host_command} ->
          if host_id == HostCore.Host.host_key() do
            Logger.info("Received stop request for host")
            Process.send_after(HostCore.Host, {:do_stop, stop_host_command["timeout"]}, 100)
            Tracer.set_status(:ok, "")
            {:reply, success_ack()}
          else
            Tracer.set_status(:error, "Incorrect host for stop command")
            {:reply, failure_ack("Handled stop request for incorrect host. Ignoring")}
          end

        {:error, e} ->
          Tracer.set_status(:error, "Failed to parse stop host command")
          Logger.error("Unable to parse incoming stop request: #{e}")
          {:reply, failure_ack("Unable to parse stop host command: #{e}")}
      end
    end
  end

  ### REGISTRY CREDENTIALS (via Config Service)
  defp handle_request({"registries", "put"}, body, _reply_to) do
    Tracer.with_span "Handle Registries Put (ctl)", kind: :server do
      with {:ok, credsmap} <- Jason.decode(body) do
        HostCore.Host.set_credsmap(credsmap)

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
  defp handle_request({"auction", "actor"}, body, _reply_to) do
    Tracer.with_span "Handle Actor Auction Request (ctl)", kind: :server do
      with {:ok, auction_request} <- Jason.decode(body),
           true <- has_values(auction_request, ["actor_ref"]) do
        host_labels = HostCore.Host.host_labels()
        required_labels = auction_request["constraints"] || %{}

        if Map.equal?(host_labels, Map.merge(host_labels, required_labels)) do
          ack = %{
            actor_ref: auction_request["actor_ref"],
            constraints: required_labels,
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
  end

  # Auction Provider
  # input: #{"actor_ref" => "...", "constraints" => %{}}
  defp handle_request({"auction", "provider"}, body, _reply_to) do
    Tracer.with_span "Handle Provider Auction Request (ctl)", kind: :server do
      with {:ok, auction_request} <- Jason.decode(body),
           true <- has_values(auction_request, ["provider_ref"]) do
        host_labels = HostCore.Host.host_labels()
        required_labels = auction_request["constraints"] || %{}
        provider_ref = auction_request["provider_ref"]
        link_name = Map.get(auction_request, "link_name", "default")

        if Map.equal?(host_labels, Map.merge(host_labels, required_labels)) &&
             !HostCore.Providers.ProviderSupervisor.provider_running?(provider_ref, link_name) do
          ack = %{
            provider_ref: provider_ref,
            link_name: link_name,
            constraints: required_labels,
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
  end

  # FALL THROUGH
  defp handle_request(tuple, _body, _reply_to) do
    Tracer.with_span "Handle Unexpected Control Command (ctl)", kind: :server do
      Logger.warn("Unexpected/unhandled lattice control command: #{inspect(tuple)}")
      Tracer.set_status(:error, "Unexpected control command: #{inspect(tuple)}")
    end
  end

  def publish_actor_start_failed(actor_ref, msg) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        actor_ref: actor_ref,
        error: msg
      }
      |> CloudEvent.new("actor_start_failed")

    topic = "wasmbus.evt.#{prefix}"

    HostCore.Nats.safe_pub(:control_nats, topic, msg)
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

    HostCore.Nats.safe_pub(:control_nats, topic, msg)
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

  # returns true if all keys have non-nil values in the map
  defp has_values(m, keys) when is_map(m) and is_list(keys) do
    Enum.all?(keys, &Map.get(m, &1))
  end

  defp has_values(_m, _keys), do: false
end

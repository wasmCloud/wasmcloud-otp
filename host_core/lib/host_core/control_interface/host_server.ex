defmodule HostCore.ControlInterface.HostServer do
  @moduledoc false
  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  use Gnat.Server

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.CloudEvent
  alias HostCore.ControlInterface.ACL
  alias HostCore.Providers.ProviderSupervisor
  alias HostCore.Vhost.VirtualHost

  import HostCore.ControlInterface.LatticeServer,
    only: [
      failure_ack: 1,
      has_values: 2,
      success_ack: 0,
      reconstitute_trace_context: 1,
      publish_actor_start_failed: 4
    ]

  def request(%{topic: topic, body: body, reply_to: reply_to} = req) do
    req
    |> Map.get(:headers)
    |> reconstitute_trace_context()

    Logger.debug("Received host control interface request on #{topic}")

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

  # Retrieves the inventory of the current host
  defp handle_request({"get", host_id, "inv"}, _body, _reply_to, prefix) do
    Tracer.with_span "Handle Inventory Request (ctl)", kind: :server do
      Tracer.set_attribute("host_id", host_id)

      case VirtualHost.lookup(host_id) do
        :error ->
          {:reply, failure_ack("Command received by incorrect host and could not be processed")}

        {:ok, {pid, _prefix}} ->
          inv = VirtualHost.get_inventory(pid)

          {:reply,
           inv
           |> ACL.convert_inv_actors(prefix)
           |> ACL.convert_inv_providers(prefix)
           |> Jason.encode!()}
      end
    end
  end

  # Launch Actor
  # %{"actor_ref" => "wasmcloud.azurecr.io/echo:0.12.0", "host_id" => "Nxxxx", "count" => 3}
  # %{"actor_ref" => "bindle://example.com/echo/0.12.0", "host_id" => "Nxxxx", "count" => 4}
  defp handle_request({"cmd", host_id, "la"}, body, _reply_to, prefix) do
    with {:ok, start_actor_command} <- Jason.decode(body),
         actor_ref <- Map.get(start_actor_command, "actor_ref"),
         true <- actor_ref != nil do
      ctx = Tracer.current_span_ctx()

      Task.Supervisor.start_child(ControlInterfaceTaskSupervisor, fn ->
        Tracer.set_current_span(ctx)

        Tracer.with_span "Handle Launch Actor Request (ctl)", kind: :server do
          count = Map.get(start_actor_command, "count", 1)
          annotations = Map.get(start_actor_command, "annotations") || %{}

          Tracer.set_attribute("count", count)
          Tracer.set_attribute("host_id", host_id)
          Tracer.set_attribute("lattice_id", prefix)

          res =
            if String.starts_with?(actor_ref, "bindle://") do
              ActorSupervisor.start_actor_from_bindle(host_id, actor_ref, count, annotations)
            else
              ActorSupervisor.start_actor_from_oci(host_id, actor_ref, count, annotations)
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

              publish_actor_start_failed(host_id, prefix, actor_ref, inspect(e))
          end
        end
      end)

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Invalid launch actor JSON request")}
    end
  end

  defp handle_request({"cmd", host_id, "sa"}, body, _reply_to, prefix) do
    Tracer.with_span "Handle Stop Actor Request (ctl)", kind: :server do
      Tracer.set_attribute("host_id", host_id)
      Tracer.set_attribute("lattice_id", prefix)

      with {:ok, stop_actor_command} <- Jason.decode(body),
           true <- has_values(stop_actor_command, ["actor_ref", "count"]) do
        ActorSupervisor.terminate_actor(
          host_id,
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
  defp handle_request({"cmd", host_id, "scale"}, body, _reply_to, _prefix) do
    with {:ok, scale_request} <- Jason.decode(body),
         true <- has_values(scale_request, ["actor_id", "actor_ref", "count"]) do
      actor_id = scale_request["actor_id"]
      actor_ref = scale_request["actor_ref"]
      count = scale_request["count"]

      ctx = Tracer.current_span_ctx()

      Task.Supervisor.start_child(ControlInterfaceTaskSupervisor, fn ->
        Tracer.set_current_span(ctx)

        Tracer.with_span "Handle Scale Actor Request (ctl)", kind: :server do
          case ActorSupervisor.scale_actor(host_id, actor_id, count, actor_ref) do
            {:error, err} ->
              Logger.error("Error scaling actor #{actor_id}: #{err}", actor_id: actor_id)

            _ ->
              :ok
          end
        end
      end)

      {:reply, success_ack()}
    else
      _ ->
        {:reply, failure_ack("Invalid scale actor JSON request")}
    end
  end

  # Update Actor
  # input: %{"new_actor_ref" => "... oci URL ..."} , public key, etc needs to match a running actor
  defp handle_request({"cmd", host_id, "upd"}, body, _reply_to, _prefix) do
    Tracer.with_span "Handle Live Update Request (ctl)", kind: :server do
      with {:ok, update_actor_command} <- Jason.decode(body),
           true <- has_values(update_actor_command, ["new_actor_ref"]) do
        # Note to the curious - we can update existing actors using nothing but the new ref (e.g. we don't need the old)
        # because a precondition is that the new ref must have the same public key as the running actor
        Tracer.set_attribute("new_actor_ref", update_actor_command["new_actor_ref"])
        span_ctx = Tracer.current_span_ctx()

        response =
          case ActorSupervisor.live_update(
                 host_id,
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
  defp handle_request({"cmd", host_id, "stop"}, body, _reply_to, _prefix) do
    Tracer.with_span "Handle Stop Host Command (ctl)", kind: :server do
      case Jason.decode(body) do
        # TODO: Right now this will contain a parameter for timeout. Obviously how this works currently
        # only results in the graceful shutdowns built into the system. There may be some inflight work
        # we want to wait for up to the timeout. We could use this library possibly so we can put in
        # hooks: https://github.com/botsquad/graceful_stop.
        {:ok, stop_host_command} ->
          case VirtualHost.lookup(host_id) do
            {:ok, {pid, _prefix}} ->
              Logger.info("Received stop request for host #{host_id}")
              VirtualHost.stop(pid, Map.get(stop_host_command, "timeout", 500))

              Tracer.set_status(:ok, "")
              {:reply, success_ack()}

            :error ->
              Tracer.set_status(:error, "Target host isn't running: #{host_id}")
              Logger.error("Target host is not running: #{host_id}")
              {:reply, failure_ack("Target host #{host_id} is not active, stop request ignored.")}
          end

        {:error, e} ->
          Tracer.set_status(:error, "Failed to parse stop host command")
          Logger.error("Unable to parse incoming stop request: #{e}")
          {:reply, failure_ack("Unable to parse stop host command: #{e}")}
      end
    end
  end

  # Launch Provider
  defp handle_request({"cmd", host_id, "lp"}, body, _reply_to, prefix) do
    with {:ok, start_provider_command} <- Jason.decode(body),
         true <- has_values(start_provider_command, ["provider_ref", "link_name"]) do
      if ProviderSupervisor.provider_running?(
           host_id,
           start_provider_command["provider_ref"],
           start_provider_command["link_name"],
           ""
         ) do
        warning =
          "Ignoring request to start provider, #{start_provider_command["provider_ref"]} (#{start_provider_command["link_name"]}) is already running"

        Logger.warn(warning)

        publish_provider_start_failed(host_id, prefix, start_provider_command, warning)
        {:reply, failure_ack("Provider with that link name is already running on this host")}
      else
        ctx = Tracer.current_span_ctx()

        Task.Supervisor.start_child(ControlInterfaceTaskSupervisor, fn ->
          Tracer.set_current_span(ctx)

          Tracer.with_span "Handle Launch Provider Request (ctl)", kind: :server do
            annotations = Map.get(start_provider_command, "annotations") || %{}

            res =
              if String.starts_with?(start_provider_command["provider_ref"], "bindle://") do
                ProviderSupervisor.start_provider_from_bindle(
                  host_id,
                  start_provider_command["provider_ref"],
                  start_provider_command["link_name"],
                  Map.get(start_provider_command, "configuration", ""),
                  annotations
                )
              else
                ProviderSupervisor.start_provider_from_oci(
                  host_id,
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

                publish_provider_start_failed(host_id, prefix, start_provider_command, inspect(e))
            end
          end
        end)

        {:reply, success_ack()}
      end
    else
      _ ->
        {:reply, failure_ack("Improperly formed start provider command JSON")}
    end
  end

  # Stop Provider
  defp handle_request({"cmd", host_id, "sp"}, body, _reply_to, _prefix) do
    Tracer.with_span "Handle Stop Provider Request (ctl)", kind: :server do
      with {:ok, stop_provider_command} <- Jason.decode(body),
           true <- has_values(stop_provider_command, ["provider_ref", "link_name"]),
           56 <- stop_provider_command |> Map.get("provider_ref", "") |> String.length() do
        Tracer.set_attribute("provider_ref", stop_provider_command["provider_ref"])
        Tracer.set_attribute("link_name", stop_provider_command["link_name"])

        ProviderSupervisor.terminate_provider(
          host_id,
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

  defp publish_provider_start_failed(host_id, prefix, command, msg) do
    %{
      provider_ref: command["provider_ref"],
      link_name: command["link_name"],
      error: msg
    }
    |> CloudEvent.new("provider_start_failed", host_id)
    |> CloudEvent.publish(prefix)
  end
end

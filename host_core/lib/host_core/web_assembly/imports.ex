defmodule HostCore.WebAssembly.Imports do
  @moduledoc false
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias HostCore.Actors.ActorModule.State
  alias HostCore.CloudEvent
  alias HostCore.Providers.Builtin.Logging
  alias HostCore.Providers.Builtin.Numbergen
  alias HostCore.Vhost.VirtualHost
  alias HostCore.WasmCloud.Native

  @wasmcloud_logging "wasmcloud:builtin:logging"
  @wasmcloud_numbergen "wasmcloud:builtin:numbergen"

  @rpc_event_prefix "wasmbus.rpcevt"

  # Once a message body reaches 900kb, we will use the object
  # store to hold it and allow 15 seconds for the RPC call to
  # finish (giving the other side time to "de-chunk")
  @chunk_threshold 900 * 1024
  @chunk_rpc_timeout 15_000

  def wapc_imports(agent) do
    %{
      __host_call:
        {:fn, [:i32, :i32, :i32, :i32, :i32, :i32, :i32, :i32], [:i32],
         fn context, bd_ptr, bd_len, ns_ptr, ns_len, op_ptr, op_len, ptr, len ->
           host_call(
             :wapc,
             context,
             bd_ptr,
             bd_len,
             ns_ptr,
             ns_len,
             op_ptr,
             op_len,
             ptr,
             len,
             agent
           )
         end},
      __console_log:
        {:fn, [:i32, :i32], [], fn context, ptr, len -> console_log(:wapc, context, ptr, len) end},
      __guest_request:
        {:fn, [:i32, :i32], [],
         fn context, op_ptr, ptr -> guest_request(:wapc, context, agent, op_ptr, ptr) end},
      __host_response:
        {:fn, [:i32], [], fn context, ptr -> host_response(:wapc, context, agent, ptr) end},
      __host_response_len:
        {:fn, [], [:i32], fn context -> host_response_len(:wapc, context, agent) end},
      __guest_response:
        {:fn, [:i32, :i32], [],
         fn context, ptr, len -> guest_response(:wapc, context, agent, ptr, len) end},
      __guest_error:
        {:fn, [:i32, :i32], [],
         fn context, ptr, len -> guest_error(:wapc, context, agent, ptr, len) end},
      __host_error:
        {:fn, [:i32], [], fn context, ptr -> host_error(:wapc, context, agent, ptr) end},
      __host_error_len: {:fn, [], [:i32], fn context -> host_error_len(:wapc, context, agent) end}
    }
  end

  def wasmbus_imports(agent) do
    %{
      __host_call:
        {:fn, [:i32, :i32, :i32, :i32, :i32, :i32, :i32, :i32], [:i32],
         fn context, bd_ptr, bd_len, ns_ptr, ns_len, op_ptr, op_len, ptr, len ->
           host_call(
             :wasmbus,
             context,
             bd_ptr,
             bd_len,
             ns_ptr,
             ns_len,
             op_ptr,
             op_len,
             ptr,
             len,
             agent
           )
         end},
      __console_log:
        {:fn, [:i32, :i32], [],
         fn context, ptr, len -> console_log(:wasmbus, context, ptr, len) end},
      __guest_request:
        {:fn, [:i32, :i32], [],
         fn context, op_ptr, ptr -> guest_request(:wasmbus, context, agent, op_ptr, ptr) end},
      __host_response:
        {:fn, [:i32], [], fn context, ptr -> host_response(:wasmbus, context, agent, ptr) end},
      __host_response_len:
        {:fn, [], [:i32], fn context -> host_response_len(:wasmbus, context, agent) end},
      __guest_response:
        {:fn, [:i32, :i32], [],
         fn context, ptr, len -> guest_response(:wasmbus, context, agent, ptr, len) end},
      __guest_error:
        {:fn, [:i32, :i32], [],
         fn context, ptr, len -> guest_error(:wasmbus, context, agent, ptr, len) end},
      __host_error:
        {:fn, [:i32], [], fn context, ptr -> host_error(:wasmbus, context, agent, ptr) end},
      __host_error_len:
        {:fn, [], [:i32], fn context -> host_error_len(:wasmbus, context, agent) end}
    }
  end

  defp console_log(_api_type, context, ptr, len) do
    text = Wasmex.Memory.read_string(context.caller, context.memory, ptr, len)

    if String.length(text) > 0 do
      Logger.info("Log from guest (non-actor): #{text}")
    end

    nil
  end

  defp host_call(
         _api_type,
         context,
         bd_ptr,
         bd_len,
         ns_ptr,
         ns_len,
         op_ptr,
         op_len,
         ptr,
         len,
         agent
       ) do
    span_ctx = Agent.get(agent, fn content -> content.parent_span end)

    Tracer.set_current_span(span_ctx)

    # Read host_call parameters from wasm memory
    payload = Wasmex.Memory.read_binary(context.caller, context.memory, ptr, len)
    binding = Wasmex.Memory.read_string(context.caller, context.memory, bd_ptr, bd_len)
    namespace = Wasmex.Memory.read_string(context.caller, context.memory, ns_ptr, ns_len)
    operation = Wasmex.Memory.read_string(context.caller, context.memory, op_ptr, op_len)

    Logger.debug("Host call: #{namespace} - #{binding}: #{operation} (#{len} bytes)")

    state = Agent.get(agent, fn content -> content end)
    config = VirtualHost.config(state.host_id)
    claims = state.claims
    actor = claims.public_key

    Tracer.with_span "Host Call", kind: :client do
      Tracer.set_attribute("namespace", namespace)
      Tracer.set_attribute("binding", binding)
      Tracer.set_attribute("operation", operation)
      Tracer.set_attribute("actor_id", actor)
      Tracer.set_attribute("host_id", config.host_key)
      Tracer.set_attribute("payload_size", byte_size(payload))

      payload = %{
        payload: payload,
        binding: binding,
        namespace: namespace,
        operation: operation,
        seed: config.cluster_seed,
        claims: claims,
        prefix: config.lattice_prefix,
        host_id: config.host_key,
        state: state,
        agent: agent,
        source_actor: actor,
        target: nil,
        authorized: false,
        verified: false
      }

      payload
      |> perform_verify()
      |> tap(&update_tracer_status/1)
    end
  end

  defp perform_verify(payload) do
    case identify_target(payload) do
      {:ok, token} ->
        token
        |> verify_link()
        |> authorize_call()
        |> invoke()

      {:error, :alias_not_found, _token = %{namespace: namespace, prefix: prefix}} ->
        Agent.update(payload.agent, fn state ->
          %State{
            state
            | host_error: "Call alias not found: #{namespace} on #{prefix}"
          }
        end)

        0
    end
  end

  defp update_tracer_status(res) do
    case res do
      0 -> Tracer.set_status(:error, "")
      1 -> Tracer.set_status(:ok, "")
    end
  end

  # Logging is a builtin and does not need a target
  defp identify_target(%{namespace: @wasmcloud_logging} = token) do
    {:ok, token}
  end

  # Numbergen is a builtin and does not need a target
  defp identify_target(%{namespace: @wasmcloud_numbergen} = token) do
    {:ok, token}
  end

  defp identify_target(token) do
    case get_target(token) do
      :unknown ->
        {:error, :alias_not_found, token}

      target ->
        {:ok, %{token | target: target}}
    end
  end

  defp get_target(%{
         namespace: namespace,
         binding: binding,
         prefix: prefix,
         source_actor: actor_id
       }) do
    case HostCore.Linkdefs.Manager.lookup_link_definition(prefix, actor_id, namespace, binding) do
      nil ->
        check_namespace(namespace, prefix)

      ld ->
        Tracer.set_attribute("target_provider", ld.provider_id)
        {:provider, ld.provider_id, "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{binding}"}
    end
  end

  defp check_namespace(namespace, prefix) do
    if String.starts_with?(namespace, "M") && String.length(namespace) == 56 do
      Tracer.set_attribute("target_actor", namespace)
      {:actor, namespace, "wasmbus.rpc.#{prefix}.#{namespace}"}
    else
      do_lookup_call_alias(namespace, prefix)
    end
  end

  defp do_lookup_call_alias(namespace, prefix) do
    case HostCore.Claims.Manager.lookup_call_alias(prefix, namespace) do
      {:ok, actor_key} ->
        Tracer.set_attribute("target_actor", actor_key)
        {:actor, actor_key, "wasmbus.rpc.#{prefix}.#{actor_key}"}

      :error ->
        :unknown
    end
  end

  # Built-in Providers do not have link definitions
  # Auto-verify the built-in contract IDs (claims check will be performed below in authorize_call)
  defp verify_link(%{namespace: @wasmcloud_logging} = token) do
    %{token | verified: true}
  end

  defp verify_link(%{namespace: @wasmcloud_numbergen} = token) do
    %{token | verified: true}
  end

  defp verify_link(%{target: {:actor, _, _}} = token) do
    %{token | verified: true}
  end

  defp verify_link(
         %{
           target: {:provider, _pk, _topic},
           source_actor: actor,
           namespace: namespace,
           binding: binding,
           prefix: prefix
         } = token
       ) do
    verified =
      case HostCore.Linkdefs.Manager.lookup_link_definition(prefix, actor, namespace, binding) do
        nil -> false
        _ -> true
      end

    %{token | verified: verified}
  end

  defp authorize_call(%{verified: false} = token) do
    %{token | authorized: false}
  end

  defp authorize_call(%{namespace: @wasmcloud_logging, claims: claims} = token) do
    %{token | authorized: Enum.member?(claims.caps, @wasmcloud_logging)}
  end

  defp authorize_call(%{namespace: @wasmcloud_numbergen, claims: claims} = token) do
    %{token | authorized: Enum.member?(claims.caps, @wasmcloud_numbergen)}
  end

  defp authorize_call(
         %{target: {:provider, _pk, _topic}, claims: claims, namespace: namespace} = token
       ) do
    %{token | authorized: Enum.member?(claims.caps, namespace)}
  end

  # allow actor-to-actor calls
  defp authorize_call(%{target: {:actor, _, _}} = token) do
    %{token | authorized: true}
  end

  # Deny invocation due to missing link definition for a contract ID and link name
  defp invoke(
         %{
           verified: false,
           agent: agent,
           namespace: namespace,
           prefix: prefix
         } = _token
       ) do
    Agent.update(agent, fn state ->
      %State{
        state
        | host_error:
            "Invocation not authorized: missing link definition for #{namespace} on #{prefix}"
      }
    end)

    0
  end

  # Deny invocation due to missing capability claim
  defp invoke(%{authorized: false, agent: agent, namespace: namespace} = _token) do
    Agent.update(agent, fn state ->
      %State{
        state
        | host_error: "Invocation not authorized: missing capability claim for #{namespace}"
      }
    end)

    0
  end

  defp invoke(
         %{
           namespace: @wasmcloud_logging,
           operation: operation,
           payload: payload,
           source_actor: actor
         } = _token
       ) do
    Logging.invoke(actor, operation, payload)
    1
  end

  defp invoke(
         %{
           namespace: @wasmcloud_numbergen,
           operation: operation,
           payload: payload,
           agent: agent
         } = _token
       ) do
    res = Numbergen.invoke(operation, payload)
    Agent.update(agent, fn state -> %State{state | host_response: res} end)
    1
  end

  defp invoke(
         %{
           authorized: true,
           verified: true,
           agent: agent,
           seed: seed,
           prefix: prefix,
           source_actor: actor,
           namespace: namespace,
           binding: binding,
           host_id: host_id,
           operation: operation,
           payload: payload,
           target: {target_type, target_key, target_subject}
         } = _token
       ) do
    timeout =
      if byte_size(payload) > @chunk_threshold do
        @chunk_rpc_timeout
      else
        config = VirtualHost.config(host_id)
        config.rpc_timeout_ms
      end

    # generate_invocation_bytes will optionally chunk out the payload
    # to the object store

    # produce a hash map containing the propagated trace context suitable for
    # storing on an invocation

    invocation_res =
      seed
      |> Native.generate_invocation_bytes(
        actor,
        target_type,
        target_key,
        namespace,
        binding,
        operation,
        payload
      )
      |> perform_rpc_invoke(target_subject, timeout, prefix)

    # unpack_invocation_response will optionally de-chunk the response payload
    # from the object store
    res =
      case unpack_invocation_response(invocation_res) do
        {1, :host_response, msg} ->
          Agent.update(agent, fn state -> %State{state | host_response: msg} end)
          1

        {0, :host_error, error} ->
          Agent.update(agent, fn state -> %State{state | host_error: error} end)
          0
      end

    Task.Supervisor.start_child(InvocationTaskSupervisor, fn ->
      publish_invocation_result(
        actor,
        namespace,
        binding,
        operation,
        byte_size(payload),
        target_type,
        target_key,
        res,
        prefix,
        host_id
      )
    end)

    res
  end

  defp publish_invocation_result(
         actor,
         namespace,
         binding,
         operation,
         payload_bytes,
         target_type,
         target_key,
         res,
         prefix,
         host_id
       ) do
    evt_type =
      if res == 1 do
        "invocation_succeeded"
      else
        "invocation_failed"
      end

    %{
      source: %{
        public_key: actor,
        contract_id: nil,
        link_name: nil
      },
      dest: %{
        public_key: target_key,
        contract_id:
          if target_type == :provider do
            namespace
          else
            nil
          end,
        link_name:
          if target_type == :provider do
            binding
          else
            nil
          end
      },
      operation: operation,
      bytes: payload_bytes
    }
    |> CloudEvent.new(evt_type, host_id)
    |> CloudEvent.publish(prefix, @rpc_event_prefix)
  end

  defp perform_rpc_invoke(inv_bytes, target_subject, timeout, prefix) do
    # Perform RPC invocation over lattice
    Tracer.with_span "Outbound RPC", kind: :client do
      Tracer.set_attribute("timeout", timeout)
      Tracer.set_attribute("topic", target_subject)
      Tracer.set_attribute("lattice_id", prefix)

      case prefix
           |> HostCore.Nats.control_connection()
           |> HostCore.Nats.safe_req(target_subject, inv_bytes, receive_timeout: timeout) do
        {:ok, %{body: body}} ->
          Tracer.set_status(:ok, "")
          body

        {:error, :no_responders} ->
          Logger.error("No responders for RPC invocation")
          Tracer.set_status(:error, "No responders")
          :fail

        {:error, :timeout} ->
          Logger.error("Timeout attempting to perform RPC invocation")
          Tracer.set_status(:error, "timeout")
          :fail
      end
    end
  end

  defp unpack_invocation_response(res) do
    case res do
      # Invocation failed due to timeout
      :fail ->
        {0, :host_error, "Failed to perform RPC call: request timeout"}

      # If invocation was successful but resulted in an error then that goes in `host_error`
      # Otherwise, InvocationResponse.msg goes in `host_response`
      _ ->
        ir = Msgpax.unpack!(res)

        if ir["error"] == nil do
          {1, :host_response, ir |> check_dechunk() |> IO.iodata_to_binary()}
        else
          {0, :host_error, ir["error"]}
        end
    end
  end

  defp safe_bsize(nil), do: 0
  defp safe_bsize(b) when is_binary(b), do: byte_size(b)

  defp check_dechunk(ir) do
    bsize = safe_bsize(Map.get(ir, "msg", <<>>))
    invid = "#{ir["invocation_id"]}-r"

    # if declared content size is greater than the actual (e.g. empty payload) then
    # we know we need to de-chunk
    with true <- Map.get(ir, "content_length", bsize) > bsize,
         {:ok, bytes} <- Native.dechunk_inv(invid) do
      bytes
    else
      {:error, e} ->
        Logger.error("Failed to dechunk invocation response: #{inspect(e)}")
        <<>>

      _ ->
        Map.get(ir, "msg", <<>>)
    end
  end

  defp host_response(_api_type, context, agent, ptr) do
    host_resp = Agent.get(agent, fn content -> content.host_response end)

    if host_resp != nil do
      Wasmex.Memory.write_binary(context.caller, context.memory, ptr, host_resp)
      nil
    end
  end

  defp host_response_len(_api_type, _context, agent) do
    host_resp = Agent.get(agent, fn content -> content.host_response end)

    if host_resp != nil do
      safe_bsize(host_resp)
    else
      0
    end
  end

  defp host_error(_api_type, context, agent, ptr) do
    host_err = Agent.get(agent, fn content -> content.host_error end)

    if host_err != nil do
      Wasmex.Memory.write_binary(context.caller, context.memory, ptr, host_err)
      nil
    end
  end

  defp host_error_len(_api_type, _context, agent) do
    host_err = Agent.get(agent, fn content -> content.host_error end)

    if host_err != nil do
      safe_bsize(host_err)
    else
      0
    end
  end

  # Load the guest response indicated by the location and length into the :guest_response state field.
  defp guest_response(_api_type, context, agent, ptr, len) do
    gr = Wasmex.Memory.read_binary(context.caller, context.memory, ptr, len)
    Agent.update(agent, fn content -> %State{content | guest_response: gr} end)

    nil
  end

  # Load the guest error indicated by the location and length into the :guest_error field
  defp guest_error(_api_type, context, agent, ptr, len) do
    ge = Wasmex.Memory.read_binary(context.caller, context.memory, ptr, len)
    Agent.update(agent, fn content -> %State{content | guest_error: ge} end)

    nil
  end

  defp guest_request(_api_type, context, agent, op_ptr, ptr) do
    # inv = HostCore.WebAssembly.ActorModule.current_invocation(actor_pid)
    inv = Agent.get(agent, fn content -> content.invocation end)

    Wasmex.Memory.write_binary(context.caller, context.memory, ptr, inv.payload)
    Wasmex.Memory.write_binary(context.caller, context.memory, op_ptr, inv.operation)

    nil
  end
end

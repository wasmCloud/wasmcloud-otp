defmodule HostCore.WebAssembly.Imports do
  @moduledoc false
  require Logger
  alias HostCore.Actors.ActorModule.State
  alias HostCore.CloudEvent

  @wasmcloud_logging "wasmcloud:builtin:logging"
  @wasmcloud_numbergen "wasmcloud:builtin:numbergen"

  # Once a message body reaches 700kb, we will use the object
  # store to hold it and allow 15 seconds for the RPC call to
  # finish (giving the other side time to "de-chunk")
  @chunk_threshold 700 * 1024
  @chunk_rpc_timeout 15000

  def fake_wasi(_agent) do
    %{
      fd_write:
        {:fn, [:i32, :i32, :i32, :i32], [:i32],
         fn _context, _a, _b, _c, _d -> suppress_fdwrite() end}
    }
  end

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

  defp suppress_fdwrite() do
    Logger.debug("Suppressed actor module call to WASI fd_write")
  end

  defp console_log(_api_type, context, ptr, len) do
    txt = Wasmex.Memory.read_string(context.memory, ptr, len)

    if txt != nil do
      Logger.info("Log from guest (non-actor): #{txt}")
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
    # Read host_call parameters from wasm memory
    payload = Wasmex.Memory.read_binary(context.memory, ptr, len)
    binding = Wasmex.Memory.read_string(context.memory, bd_ptr, bd_len)
    namespace = Wasmex.Memory.read_string(context.memory, ns_ptr, ns_len)
    operation = Wasmex.Memory.read_string(context.memory, op_ptr, op_len)

    Logger.debug("host call: #{namespace} - #{binding}: #{operation} (#{len} bytes)")

    seed = HostCore.Host.cluster_seed()
    prefix = HostCore.Host.lattice_prefix()
    state = Agent.get(agent, fn content -> content end)
    claims = state.claims
    actor = claims.public_key

    %{
      payload: payload,
      binding: binding,
      namespace: namespace,
      operation: operation,
      seed: seed,
      claims: claims,
      prefix: prefix,
      state: state,
      agent: agent,
      source_actor: actor,
      target: nil,
      authorized: false,
      verified: false
    }
    |> identify_target()
    |> verify_link()
    |> authorize_call()
    |> invoke()
  end

  defp identify_target(
         token = %{
           namespace: namespace,
           binding: binding,
           prefix: prefix,
           source_actor: actor_id
         }
       ) do
    target =
      case HostCore.Linkdefs.Manager.lookup_link_definition(actor_id, namespace, binding) do
        {:ok, ld} ->
          {:provider, ld.provider_id, "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{binding}"}

        _ ->
          if String.starts_with?(namespace, "M") && String.length(namespace) == 56 do
            {:actor, namespace, "wasmbus.rpc.#{prefix}.#{namespace}"}
          else
            case lookup_call_alias(namespace) do
              {:ok, actor_key} ->
                {:actor, actor_key, "wasmbus.rpc.#{prefix}.#{actor_key}"}

              :error ->
                :unknown
            end
          end
      end

    %{token | target: target}
  end

  # Built-in Providers do not have link definitions
  # Auto-verify the built-in contract IDs (claims check will be performed below in authorize_call)
  defp verify_link(token = %{namespace: @wasmcloud_logging}) do
    %{token | verified: true}
  end

  defp verify_link(token = %{namespace: @wasmcloud_numbergen}) do
    %{token | verified: true}
  end

  defp verify_link(token = %{target: :unknown}) do
    %{token | verified: false}
  end

  defp verify_link(token = %{target: {:actor, _, _}}) do
    %{token | verified: true}
  end

  defp verify_link(
         token = %{
           target: {:provider, _pk, _topic},
           source_actor: actor,
           namespace: namespace,
           binding: binding
         }
       ) do
    verified =
      case HostCore.Linkdefs.Manager.lookup_link_definition(actor, namespace, binding) do
        {:ok, _ld} -> true
        _ -> false
      end

    %{token | verified: verified}
  end

  defp authorize_call(token = %{verified: false}) do
    %{token | authorized: false}
  end

  defp authorize_call(token = %{namespace: @wasmcloud_logging, claims: claims}) do
    %{token | authorized: Enum.member?(claims.caps, @wasmcloud_logging)}
  end

  defp authorize_call(token = %{namespace: @wasmcloud_numbergen, claims: claims}) do
    %{token | authorized: Enum.member?(claims.caps, @wasmcloud_numbergen)}
  end

  defp authorize_call(
         token = %{target: {:provider, _pk, _topic}, claims: claims, namespace: namespace}
       ) do
    %{token | authorized: Enum.member?(claims.caps, namespace)}
  end

  # allow actor-to-actor calls
  defp authorize_call(token = %{target: {:actor, _, _}}) do
    %{token | authorized: true}
  end

  defp invoke(_token = %{authorized: false, agent: agent, namespace: namespace}) do
    Agent.update(agent, fn state ->
      %State{state | host_error: "Invocation not authorized: missing claim for #{namespace}"}
    end)

    0
  end

  defp invoke(
         _token = %{
           namespace: @wasmcloud_logging,
           operation: operation,
           payload: payload,
           source_actor: actor
         }
       ) do
    HostCore.Providers.Builtin.Logging.invoke(actor, operation, payload)
    1
  end

  defp invoke(
         _token = %{
           namespace: @wasmcloud_numbergen,
           operation: operation,
           payload: payload,
           agent: agent
         }
       ) do
    res = HostCore.Providers.Builtin.Numbergen.invoke(operation, payload)
    Agent.update(agent, fn state -> %State{state | host_response: res} end)
    1
  end

  defp invoke(_token = %{verified: false, agent: agent}) do
    Agent.update(agent, fn state -> %State{state | host_error: "Invocation not authorized"} end)
    0
  end

  defp invoke(
         _token = %{
           authorized: true,
           verified: true,
           agent: agent,
           seed: seed,
           source_actor: actor,
           namespace: namespace,
           binding: binding,
           operation: operation,
           payload: payload,
           target: {target_type, target_key, target_subject}
         }
       ) do
    timeout =
      if byte_size(payload) > @chunk_threshold do
        @chunk_rpc_timeout
      else
        HostCore.Host.rpc_timeout()
      end

    # generate_invocation_bytes will optionally chunk out the payload
    # to the object store
    invocation_res =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        actor,
        target_type,
        target_key,
        namespace,
        binding,
        operation,
        payload
      )
      |> perform_rpc_invoke(target_subject, timeout)

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

    Task.start(fn ->
      publish_invocation_result(
        actor,
        namespace,
        binding,
        operation,
        byte_size(payload),
        target_type,
        target_key,
        res
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
         res
       ) do
    evt_type =
      if res == 1 do
        "invocation_succeeded"
      else
        "invocation_failed"
      end

    prefix = HostCore.Host.lattice_prefix()

    msg =
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
      |> CloudEvent.new(evt_type)

    topic = "wasmbus.evt.#{prefix}"
    HostCore.Nats.safe_pub(:control_nats, topic, msg)
  end

  defp lookup_call_alias(call_alias) do
    case :ets.lookup(:callalias_table, call_alias) do
      [{_call_alias, pkey}] ->
        {:ok, pkey}

      [] ->
        :error
    end
  end

  defp perform_rpc_invoke(inv_bytes, target_subject, timeout) do
    # Perform RPC invocation over lattice
    case HostCore.Nats.safe_req(:lattice_nats, target_subject, inv_bytes, receive_timeout: timeout) do
      {:ok, %{body: body}} -> body
      {:error, :timeout} -> :fail
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
        ir = res |> Msgpax.unpack!()

        if ir["error"] == nil do
          {1, :host_response, check_dechunk(ir) |> IO.iodata_to_binary()}
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
         {:ok, bytes} <- HostCore.WasmCloud.Native.dechunk_inv(invid) do
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
    if (hr = Agent.get(agent, fn content -> content.host_response end)) != nil do
      Wasmex.Memory.write_binary(context.memory, ptr, hr)
      nil
    end
  end

  defp host_response_len(_api_type, _context, agent) do
    if (hr = Agent.get(agent, fn content -> content.host_response end)) != nil do
      safe_bsize(hr)
    else
      0
    end
  end

  defp host_error(_api_type, context, agent, ptr) do
    if (he = Agent.get(agent, fn content -> content.host_error end)) != nil do
      Wasmex.Memory.write_binary(context.memory, ptr, he)
      nil
    end
  end

  defp host_error_len(_api_type, _context, agent) do
    if (he = Agent.get(agent, fn content -> content.host_error end)) != nil do
      safe_bsize(he)
    else
      0
    end
  end

  # Load the guest response indicated by the location and length into the :guest_response state field.
  defp guest_response(_api_type, context, agent, ptr, len) do
    memory = context.memory
    gr = Wasmex.Memory.read_binary(memory, ptr, len)
    Agent.update(agent, fn content -> %State{content | guest_response: gr} end)

    nil
  end

  # Load the guest error indicated by the location and length into the :guest_error field
  defp guest_error(_api_type, context, agent, ptr, len) do
    memory = context.memory

    ge = Wasmex.Memory.read_binary(memory, ptr, len)
    Agent.update(agent, fn content -> %State{content | guest_error: ge} end)

    nil
  end

  defp guest_request(_api_type, context, agent, op_ptr, ptr) do
    memory = context.memory
    # inv = HostCore.WebAssembly.ActorModule.current_invocation(actor_pid)
    inv = Agent.get(agent, fn content -> content.invocation end)

    Wasmex.Memory.write_binary(memory, ptr, inv.payload)
    Wasmex.Memory.write_binary(memory, op_ptr, inv.operation)

    nil
  end
end

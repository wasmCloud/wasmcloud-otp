defmodule HostCore.WebAssembly.Imports do
  require Logger
  alias HostCore.Actors.ActorModule.State

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
    txt = Wasmex.Memory.read_string(context.memory, ptr, len)

    if txt != nil do
      Logger.info("Log from guest: #{txt}")
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

    Logger.info("host call: #{namespace} - #{binding}: #{operation} (#{len} bytes)")

    seed = HostCore.Host.seed()
    prefix = HostCore.Host.lattice_prefix()
    state = Agent.get(agent, fn content -> content end)
    claims = state.claims
    actor = claims.public_key

    provider_key =
      case HostCore.Providers.lookup_provider(namespace, binding) do
        {:ok, pk} -> pk
        :error -> ""
      end

    case HostCore.Linkdefs.Manager.lookup_link_definition(actor, namespace, binding) do
      # Authorize actor to invoke provider over link definition
      {:ok, _ld} ->
        authorize(
          actor,
          binding,
          namespace,
          operation,
          payload,
          claims,
          seed,
          prefix,
          provider_key,
          state
        )
        |> finish_host_call(agent)

      # Link definition not found for actor, could be attempting to call a call alias
      :error ->
        case lookup_call_alias(namespace) do
          {:ok, actor_key} ->
            finish_host_call(
              {:ok, actor_key, binding, namespace, operation, payload, claims, seed, prefix,
               provider_key, state},
              agent
            )

          :error ->
            Logger.error("Failed to find link definition or call alias for invocation")
            0
        end
    end
  end

  defp authorize(
         actor,
         binding,
         namespace,
         operation,
         payload,
         claims,
         seed,
         prefix,
         provider_key,
         state
       ) do
    # TODO - check claims to make sure actor is authorized
    {:ok, actor, binding, namespace, operation, payload, claims, seed, prefix, provider_key,
     state}
  end

  defp lookup_call_alias(call_alias) do
    case :ets.lookup(:callalias_table, call_alias) do
      [{_call_alias, pkey}] ->
        {:ok, pkey}

      [] ->
        :error
    end
  end

  defp finish_host_call(
         {:ok, actor, binding, namespace, operation, payload, _claims, seed, prefix, provider_key,
          state},
         agent
       ) do
    invocation_res =
      case determine_target(provider_key, actor, prefix, binding) do
        # Unknown target automatically fails invocation
        :unknown ->
          :fail

        {target_type, target_key, target_subject} ->
          # Generate invocation and make RPC call
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
          |> invoke(target_subject)
      end

    case unpack_invocation_response(invocation_res) do
      {1, :host_response, msg} ->
        Agent.update(agent, fn _ -> %State{state | host_response: msg} end)
        1

      {0, :host_error, error} ->
        Agent.update(agent, fn _ -> %State{state | host_error: error} end)
        0
    end
  end

  defp determine_target(provider_key, actor_key, prefix, binding) do
    cond do
      String.starts_with?(provider_key, "V") && String.length(provider_key) == 56 ->
        {:provider, provider_key, "wasmbus.rpc.#{prefix}.#{provider_key}.#{binding}"}

      String.starts_with?(actor_key, "M") && String.length(actor_key) == 56 ->
        {:actor, actor_key, "wasmbus.rpc.#{prefix}.#{actor_key}"}

      true ->
        :unknown
    end
  end

  defp invoke(inv_bytes, target_subject) do
    # Perform RPC invocation over lattice
    case Gnat.request(:lattice_nats, target_subject, inv_bytes, receive_timeout: 2_000) do
      {:ok, %{body: body}} -> body
      {:error, :timeout} -> :fail
    end
  end

  defp unpack_invocation_response(res) do
    case res do
      # Invocation failed
      :fail ->
        {0, :host_error, "Failed to perform RPC call"}

      # If invocation was successful but resulted in an error then that goes in `host_error`
      # Otherwise, InvocationResponse.msg goes in `host_response`
      _ ->
        ir = res |> Msgpax.unpack!()

        if ir["error"] == nil do
          {1, :host_response, ir["msg"]}
        else
          {0, :host_error, ir["error"]}
        end
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
      byte_size(hr)
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
      byte_size(he)
    else
      0
    end
  end

  # Load the guest response indicated by the location and length into the :guest_response state field.
  defp guest_response(_api_type, context, agent, ptr, len) do
    Logger.info("Guest response")
    memory = context.memory
    gr = Wasmex.Memory.read_binary(memory, ptr, len)
    Agent.update(agent, fn content -> %State{content | guest_response: gr} end)

    nil
  end

  # Load the guest error indicated by the location and length into the :guest_error field
  defp guest_error(_api_type, context, agent, ptr, len) do
    Logger.info("Guest error")
    memory = context.memory

    ge = Wasmex.Memory.read_binary(memory, ptr, len)
    Agent.update(agent, fn content -> %State{content | guest_error: ge} end)

    nil
  end

  defp guest_request(_api_type, context, agent, op_ptr, ptr) do
    Logger.info("Guest request")
    memory = context.memory
    # inv = HostCore.WebAssembly.ActorModule.current_invocation(actor_pid)
    inv = Agent.get(agent, fn content -> content.invocation end)

    Logger.info("Got current invocation")
    Wasmex.Memory.write_binary(memory, ptr, inv.payload)
    Wasmex.Memory.write_binary(memory, op_ptr, inv.operation)

    nil
  end
end

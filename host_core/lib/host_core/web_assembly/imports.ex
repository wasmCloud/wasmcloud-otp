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

  def frodobuf_imports(agent) do
    %{
      __host_call:
        {:fn, [:i32, :i32, :i32, :i32, :i32, :i32, :i32, :i32], [:i32],
         fn context, bd_ptr, bd_len, ns_ptr, ns_len, op_ptr, op_len, ptr, len ->
           host_call(
             :frodo,
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
         fn context, ptr, len -> console_log(:frodo, context, ptr, len) end},
      __guest_request:
        {:fn, [:i32, :i32], [],
         fn context, op_ptr, ptr -> guest_request(:frodo, context, agent, op_ptr, ptr) end},
      __host_response:
        {:fn, [:i32], [], fn context, ptr -> host_response(:frodo, context, agent, ptr) end},
      __host_response_len:
        {:fn, [], [:i32], fn context -> host_response_len(:frodo, context, agent) end},
      __guest_response:
        {:fn, [:i32, :i32], [],
         fn context, ptr, len -> guest_response(:frodo, context, agent, ptr, len) end},
      __guest_error:
        {:fn, [:i32, :i32], [],
         fn context, ptr, len -> guest_error(:frodo, context, agent, ptr, len) end},
      __host_error:
        {:fn, [:i32], [], fn context, ptr -> host_error(:frodo, context, agent, ptr) end},
      __host_error_len:
        {:fn, [], [:i32], fn context -> host_error_len(:frodo, context, agent) end}
    }
  end

  defp console_log(_api_type, context, ptr, len) do
    if txt = Wasmex.Memory.read_binary(context.memory, ptr, len) != nil do
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
    Logger.info("host call")

    # Also need to look up the public key of the provider known to support
    # the given namespace and binding, e.g. "wasmcloud:httpserver"/"default"
    state = Agent.get(agent, fn content -> content end)
    claims = state.claims
    actor = claims.subject
    payload = Wasmex.Memory.read_binary(context.memory, ptr, len)
    binding = Wasmex.Memory.read_string(context.memory, bd_ptr, bd_len)
    namespace = Wasmex.Memory.read_string(context.memory, ns_ptr, ns_len)
    operation = Wasmex.Memory.read_string(context.memory, op_ptr, op_len)

    provider_key =
      case HostCore.Providers.lookup_provider(namespace, binding) do
        {:ok, pk} -> pk
        {:error} -> ""
      end

    seed = HostCore.Host.seed()
    prefix = HostCore.Host.lattice_prefix()

    Logger.info("host call: #{namespace} - #{binding}: #{operation} (#{len} bytes)")

    # Start auth chain by looking up the link definition for this call
    HostCore.LinkdefsManager.lookup_link_definition(actor, namespace, binding)
    |> authorize(
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
    |> finish()
  end

  defp authorize(
         {:ok, ld},
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
    {:ok, actor, binding, namespace, operation, payload, claims, seed, prefix, provider_key}
  end

  defp authorize(
         :error,
         _actor,
         _binding,
         _namespace,
         _operation,
         _payload,
         _claims,
         _seed,
         _prefix,
         _provider_key,
         _state
       ) do
    :error
  end

  defp finish(
         {:ok, actor, binding, namespace, operation, payload, claims, seed, prefix, provider_key,
          state}
       ) do
    # Perform RPC invocation over lattice
    # If fails, error goes in `host_error`
    # If success, if InvocationResponse.error then that goes in `host_error`
    # else InvocationResponse.msg goes in `host_response`
    {target_type, target_key, target_subject} =
      cond do
        String.starts_with?(namespace, "M") ->
          {:actor, namespace, "wasmbus.rpc.#{prefix}.#{namespace}"}

        [{_call_alias, pkey}] = :ets.lookup(:callalias_registry, {namespace}) ->
          {:actor, namespace, "wasmbus.rpc.#{prefix}.#{pkey}"}

        true ->
          {:provider, provider_key, "wasmbus.rpc.#{prefix}.#{provider_key}.#{binding}"}
      end

    inv_bytes =
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

    # make the RPC call

    res =
      case Gnat.request(:lattice_nats, target_subject, inv_bytes, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    if res != :fail do
      ir = res |> Msgpax.unpack!()

      if ir["error"] == nil do
        state = %State{
          state
          | host_response: ir["msg"] |> :binary.list_to_bin() |> Msgpax.unpack!()
        }

        1
      else
        # error field on invocation result is an optional string
        state = %State{state | host_error: ir["error"]}
        0
      end
    else
      state = %State{state | host_error: "Failed to perform RPC call"}
      0
    end
  end

  defp finish(:error) do
    0
  end

  defp host_response(_api_type, context, agent, ptr) do
    if hr = Agent.get(agent, fn content -> content.host_response end) != nil do
      Wasmex.Memory.write_binary(context.memory, ptr, byte_size(hr))
    end
  end

  defp host_response_len(_api_type, _context, agent) do
    if hr = Agent.get(agent, fn content -> content.host_response end) != nil do
      byte_size(hr)
    else
      0
    end
  end

  defp host_error(_api_type, context, agent, ptr) do
    if he = Agent.get(agent, fn content -> content.host_error end) != nil do
      Wasmex.Memory.write_binary(context.memory, ptr, byte_size(he))
    end
  end

  defp host_error_len(_api_type, _context, agent) do
    if he = Agent.get(agent, fn content -> content.host_error end) != nil do
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

  defp bsize(a) when is_binary(a) do
    byte_size(a)
  end

  defp bsize(nil), do: 0
end

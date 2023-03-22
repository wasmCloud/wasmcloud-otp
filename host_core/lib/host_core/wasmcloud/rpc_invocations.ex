defmodule HostCore.WasmCloud.RpcInvocations do
  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  alias HostCore.CloudEvent
  alias HostCore.Vhost.VirtualHost
  alias HostCore.WasmCloud.Native

  # Once a message body reaches 900kb, we will use the object
  # store to hold it and allow 15 seconds for the RPC call to
  # finish (giving the other side time to "de-chunk")
  @chunk_threshold 900 * 1024
  @chunk_rpc_timeout 15_000
  @rpc_event_prefix "wasmbus.rpcevt"
  @url_scheme "wasmbus"

  # TARGET

  def identify_target(token) do
    case get_target(token) do
      :unknown ->
        %{token | error: "Could not identify suitable target for invocation"}

      target ->
        %{token | target: target}
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

  # CALL AUTH

  def authorize_call(%{verified: false} = token) do
    %{token | authorized: false}
  end

  def authorize_call(
        %{target: {:provider, _pk, _topic}, claims: claims, namespace: namespace} = token
      ) do
    %{token | authorized: Enum.member?(Map.get(claims, :caps, []), namespace)}
  end

  # allow actor-to-actor calls
  def authorize_call(%{target: {:actor, _, _}} = token) do
    %{token | authorized: true}
  end

  # LINKS

  # Built-in Providers do not have link definitions
  # their implementations are already handled either in the NIF or in wasmCloud runtime

  # default behavior is to allow actor-to-actor calls
  def verify_link(%{target: {:actor, _, _}} = token) do
    %{token | verified: true}
  end

  def verify_link(
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

  # Reject verification of tokens that have no identified target
  def verify_link(%{target: nil} = token) do
    %{token | verified: false}
  end

  # RPC

  # Deny invocation due to missing link definition for a contract ID and link name
  def rpc_invoke(
        %{
          verified: false,
          namespace: namespace,
          prefix: prefix
        } = token
      ) do
    {:error,
     %{
       token
       | error: "Invocation not authorized: missing link definition for #{namespace} on #{prefix}"
     }}
  end

  # Deny invocation due to missing capability claim
  def rpc_invoke(%{authorized: false, namespace: namespace} = token) do
    {:error,
     %{token | error: "Invocation not authorized: missing capability claim for #{namespace}"}}
  end

  def rpc_invoke(
        %{
          authorized: true,
          verified: true,
          seed: seed,
          prefix: prefix,
          source_actor: actor,
          namespace: namespace,
          binding: binding,
          host_id: host_id,
          operation: operation,
          payload: payload,
          target: {target_type, target_key, target_subject}
        } = token
      ) do
    content_length = byte_size(payload)

    timeout =
      if content_length > @chunk_threshold do
        @chunk_rpc_timeout
      else
        config = VirtualHost.config(host_id)
        config.rpc_timeout_ms
      end

    # produce a hash map containing the propagated trace context suitable for
    # storing on an invocation
    inv_id = UUID.uuid4()

    origin = %{
      public_key: actor,
      contract_id: "",
      link_name: ""
    }

    target =
      if target_type == :actor do
        %{
          public_key: target_key,
          contract_id: "",
          link_name: ""
        }
      else
        %{
          public_key: target_key,
          contract_id: namespace,
          link_name: binding
        }
      end

    {:ok, {host_id, encoded_claims}} =
      Native.encoded_claims(
        seed,
        inv_id,
        "#{inv_url(target)}/#{operation}",
        inv_url(origin),
        payload,
        operation
      )

    inv = %{
      origin: origin,
      target: target,
      operation: operation,
      id: inv_id,
      encoded_claims: encoded_claims,
      host_id: host_id,
      content_length: content_length
    }

    inv =
      if content_length >= @chunk_threshold do
        Native.chunk_inv(inv_id, payload)
        # When the invocation is chunked, we retrieve the msg bytes from the object
        # store. The msg is disregarded and can be an empty array
        inv
        |> Map.put(:msg, [])
      else
        inv
        |> Map.put(:msg, payload)
      end

    invocation_res =
      inv
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()
      |> perform_rpc_invoke(target_subject, timeout, prefix)

    # invocation_res =
    #   seed
    #   |> Native.generate_invocation_bytes(
    #     actor,
    #     target_type,
    #     target_key,
    #     namespace,
    #     binding,
    #     operation,
    #     payload
    #   )
    #   |> perform_rpc_invoke(target_subject, timeout, prefix)

    # unpack_invocation_response will optionally de-chunk the response payload
    # from the object store
    res =
      case unpack_invocation_response(invocation_res) do
        {1, :host_response, msg} ->
          {:ok, %{token | result: msg}}

        {0, :host_error, error} ->
          {:error, %{token | error: error}}
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
      case res do
        {:ok, _} ->
          "invocation_succeeded"

        {:error, _} ->
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

  def update_tracer_status({:error, %{error: e}}), do: Tracer.set_status(:error, e)
  def update_tracer_status({:ok, _}), do: Tracer.set_status(:ok, "")

  # Helper function to determine the URL of a wasmCloud entity
  def inv_url(%{public_key: public_key, contract_id: contract_id, link_name: link_name}) do
    if public_key |> String.upcase() |> String.starts_with?("M") do
      "#{@url_scheme}://#{public_key}"
    else
      contract_id =
        contract_id |> String.replace(":", "/") |> String.replace(" ", "_") |> String.downcase()

      link_name = link_name |> String.replace(" ", "_") |> String.downcase()
      "#{@url_scheme}://#{contract_id}/#{link_name}/#{public_key}"
    end
  end
end

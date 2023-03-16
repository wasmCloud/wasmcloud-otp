defmodule HostCore.WasmCloud.Runtime.Server do
  @moduledoc """
  This GenServer encapsulates access to the underlying wasmCloud runtime used for everything from
  execution of WebAssembly modules/components to verifying signatures, claims, and many other
  interactions with the wasmCloud ecosystem and lattices. This server should be the _only_ means
  by which code in this host accesses the underlying runtime
  """
  use GenServer
  require Logger

  alias HostCore.WasmCloud.Runtime.Config, as: RuntimeConfig
  alias HostCore.WasmCloud.Runtime.ActorReference

  import HostCore.WasmCloud.RpcInvocations

  @doc """
  Starts this server with the supplied configuration. This configuration corresponds to the configuration
  required by the Rust wasmCloud runtime SDK so it needs to be kept in agreement with the equivalent data
  type in the NIF
  """
  @spec start_link(RuntimeConfig.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(%RuntimeConfig{} = config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Returns the runtime server corresponding to the given virtual host. There should always be one runtime server
  process per virtual host.
  """
  @spec runtime_for_host(host_id :: binary()) :: {:ok, pid} | :error
  def runtime_for_host(host_id) do
    case HostCore.Vhost.VirtualHost.lookup(host_id) do
      {:ok, {pid, _lattice_id}} ->
        {:ok, HostCore.Vhost.VirtualHost.get_runtime(pid)}

      _ ->
        :error
    end
  end

  @doc """
  Init portion of the genserver startup chain. Instantiates a new reference to the Rust runtime and retains
  that reference in state
  """
  @impl true
  def init(%RuntimeConfig{} = config) do
    {:ok, runtime} = HostCore.WasmCloud.Runtime.new(config)

    {:ok, {runtime, config}}
  end

  def version(pid) do
    GenServer.call(pid, :get_version)
  end

  @spec precompile_actor(pid :: pid(), bytes :: binary()) ::
          {:ok, ActorReference.t()} | {:error, binary()}
  def precompile_actor(pid, bytes) do
    GenServer.call(pid, {:precompile_actor, bytes})
  end

  @spec invoke_actor(
          pid :: pid(),
          actor_reference :: ActorReference.t(),
          operation :: binary(),
          payload :: binary()
        ) :: {:ok, binary()} | {:error, binary()}
  def invoke_actor(pid, actor_reference, operation, payload) do
    GenServer.call(pid, {:invoke_actor, actor_reference, operation, payload})
  end

  @impl true
  def handle_call(:get_version, _from, {runtime, _config} = state) do
    {:reply, HostCore.WasmCloud.Runtime.version(runtime), state}
  end

  # calls into the NIF to invoke the given operation on the indicated actor instance
  @impl true
  def handle_call({:invoke_actor, actor_reference, operation, payload}, from, state) do
    :ok =
      HostCore.WasmCloud.Runtime.call_actor(
        actor_reference,
        operation,
        payload,
        from
      )

    {:noreply, state}
  end

  # calls into the NIF to call into the runtime instance to create a new actor
  @impl true
  def handle_call({:precompile_actor, bytes}, _from, {runtime, _config} = state) do
    {:reply, HostCore.WasmCloud.Runtime.start_actor(runtime, bytes), state}
  end

  # this gets called from inside the NIF to indicate that a function call has completed
  # the `from` here is the same from (via passthrough) that came from the
  # GenServer call to `:invoke_actor`
  @impl true
  def handle_info({:returned_function_call, result, from}, state) do
    # the binary comes out of the NIF as  {:ok, vec<u8>} or {:error, vec<u8>}
    # so we need to turn the second element from a vec<u8> into a << ...>> binary
    bindata = elem(result, 1)

    bindata =
      cond do
        is_nil(bindata) ->
          <<>>

        is_binary(bindata) && byte_size(bindata) == 0 ->
          <<>>

        true ->
          IO.iodata_to_binary(bindata)
      end

    code = elem(result, 0)
    result = {code, bindata}

    GenServer.reply(from, result)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:invoke_callback, claims, binding, namespace, operation, payload, token},
        {_runtime, config} = state
      ) do
    # This callback is invoked by the wasmcloud::Runtime's host call handler
    payload = payload |> IO.iodata_to_binary()
    # TODO
    {success, return_value} =
      try do
        do_invocation(claims, binding, namespace, operation, payload, config)
      rescue
        e in RuntimeError -> {false, e.message}
      end

    :ok = HostCore.WasmCloud.Native.instance_receive_callback_result(token, success, return_value)
    {:noreply, state}
  end

  defp do_invocation(claims, binding, namespace, operation, payload, rt_config) do
    host_config = HostCore.Vhost.VirtualHost.config(rt_config.host_id)
    actor = claims.public_key

    final_res =
      %{
        payload: payload,
        binding: binding,
        namespace: namespace,
        operation: operation,
        seed: host_config.cluster_seed,
        claims: claims,
        prefix: host_config.lattice_prefix,
        host_id: host_config.host_key,
        source_actor: actor,
        target: nil,
        authorized: false,
        verified: false,
        result: nil,
        error: nil
      }
      |> identify_target()
      |> verify_link()
      |> authorize_call()
      |> rpc_invoke()
      |> tap(&update_tracer_status/1)

    case final_res do
      {:ok, %{result: r}} ->
        {true, r}

      {:error, %{error: e}} ->
        {false, e}
    end
  end
end

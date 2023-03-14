defmodule HostCore.WasmCloud.Runtime.Server do
  use GenServer
  require Logger

  @spec start_link(HostCore.WasmCloud.Runtime.Config.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(%HostCore.WasmCloud.Runtime.Config{} = config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Returns the runtime server corresponding to the given virtual host
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

  @impl true
  def init(%HostCore.WasmCloud.Runtime.Config{} = config) do
    {:ok, runtime} = HostCore.WasmCloud.Runtime.new(config)

    {:ok, runtime}
  end

  def version(pid) do
    GenServer.call(pid, :get_version)
  end

  @spec dispense_actor(pid :: pid(), bytes :: binary()) ::
          {:ok, ActorReference.t()} | {:error, binary()}
  def dispense_actor(pid, bytes) do
    GenServer.call(pid, {:dispense_actor, bytes})
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
  def handle_call(:get_version, _from, state) do
    {:reply, HostCore.WasmCloud.Runtime.version(state), state}
  end

  # calls into the NIF to invoke the given operation on the indicated actor instance
  @impl true
  def handle_call({:invoke_actor, actor_reference, operation, payload}, from, state) do
    {:reply,
     HostCore.WasmCloud.Runtime.call_actor(
       state,
       actor_reference,
       operation,
       payload,
       from
     ), state}
  end

  # calls into the NIF to call into the runtime instance to create a new actor
  @impl true
  def handle_call({:dispense_actor, bytes}, _from, state) do
    {:reply, HostCore.WasmCloud.Runtime.start_actor(state, bytes), state}
  end

  # this gets called from inside the NIF to indicate that a function call has completed
  # the `from` here is the same from (via passthrough) that came from the
  # GenServer call to `:invoke_actor`
  @impl true
  def handle_info({:returned_function_call, result, from}, state) do
    GenServer.reply(from, result)
    {:noreply, state}
  end

  @impl true
  def handle_info({:invoke_callback, claims, namespace, operation, payload, token}, state) do
    Logger.info("Handling invoke callback")
    # TODO
    {success, return_value} =
      try do
        do_invocation()
      rescue
        e in RuntimeError -> {false, e.message}
      end

    :ok = HostCore.WasmCloud.Native.instance_receive_callback_result(token, success, return_value)
    {:noreply, state}
  end

  defp do_invocation() do
    {true, <<>>}
    # TODO
  end
end

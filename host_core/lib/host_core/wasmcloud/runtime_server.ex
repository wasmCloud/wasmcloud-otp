defmodule HostCore.WasmCloud.Runtime.Server do
  use GenServer



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
        {:ok, pid}
      _ ->
        :error
    end
  end

  def init(%HostCore.WasmCloud.Runtime.Config{} = config) do
    {:ok, runtime} =
      HostCore.WasmCloud.Runtime.new(config)

    {:ok, runtime}
  end

  def version(pid) do
    GenServer.call(pid, :get_version)
  end

  @spec dispense_actor(pid :: pid(), bytes :: binary()) :: {:ok, ActorReference.t()} | {:error, binary()}
  def dispense_actor(pid, bytes) do
    GenServer.call(pid, {:dispense_actor, bytes})
  end

  @spec invoke_actor(pid :: pid(), actor_reference :: ActorReference.t(), operation :: binary(), payload :: binary()) :: {:ok, binary()} | {:error, binary()}
  def invoke_actor(pid, actor_reference, operation, payload) do
    GenServer.call(pid, {:invoke_actor, actor_reference, operation, payload})
  end

  def handle_call(:get_version, _from, state) do
    {:reply, HostCore.WasmCloud.Runtime.version(state), state}
  end

  # calls into the NIF to invoke the given operation on the indicated actor instance
  def handle_call({:invoke_actor, actor_reference, operation, payload}, from, state) do
    HostCore.WasmCloud.Runtime.call_actor(state.runtime, actor_reference, operation, payload, from)
  end

  # calls into the NIF to call into the runtime instance to create a new actor
  def handle_call({:dispense_actor, bytes}, _from, state) do
    {:ok, actor_reference} = HostCore.WasmCloud.Runtime.start_actor(state.runtime, bytes)

    {:ok, actor_reference, state}
  end
end

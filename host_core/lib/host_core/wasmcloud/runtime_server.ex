defmodule HostCore.WasmCloud.Runtime.Server do
  use GenServer

  defmodule ActorReference do
    @type t :: %__MODULE__{
      resource: binary(),
      reference: reference()
    }
    defstruct resource: nil,
              reference: nil
  end

  @spec start_link(HostCore.WasmCloud.Runtime.Config.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(%HostCore.WasmCloud.Runtime.Config{} = config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init(%HostCore.WasmCloud.Runtime.Config{} = config) do
    {:ok, runtime} =
      HostCore.WasmCloud.Runtime.new(config)

    {:ok, runtime}
  end

  @spec dispense_actor(pid :: pid(), bytes :: binary()) :: {:ok, ActorReference.t()} | {:error, binary()}
  def dispense_actor(pid, bytes) do
    GenServer.call(pid, {:dispense_actor, bytes})
  end

  def handle_call({:dispense_actor, bytes}, _from, state) do
    {:ok, actor_reference} = HostCore.WasmCloud.Native.start_actor(state.runtime)
    IO.inspect(actor_reference)

    {:error, "not yet implemented"}
  end
end

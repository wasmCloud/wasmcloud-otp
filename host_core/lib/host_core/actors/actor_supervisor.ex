defmodule HostCore.Actors.ActorSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_actor(binary) ::
          :ignore | {:error, any} | {:ok, pid} | {:stop, any} | {:ok, pid, any}
  def start_actor(bytes) when is_binary(bytes) do
    case HostCore.WasmCloud.Native.extract_claims(bytes) do
      {:error, err} ->
        Logger.error("Failed to extract claims from WebAssembly module")
        {:stop, err}

      claims ->
        DynamicSupervisor.start_child(__MODULE__, {HostCore.Actors.ActorModule, {claims, bytes}})
    end
  end

  @doc """
  Produces a map with the key being the public key of the actor and the value being a _list_
  of all of the pids (running instances) of that actor.
  """
  def all_actors() do
    Supervisor.which_children(HostCore.Actors.ActorSupervisor)
    |> Enum.map(fn {_id, pid, _type_, _modules} ->
      {HostCore.Actors.ActorModule.claims(pid).public_key, pid}
    end)
    |> Enum.group_by(fn {k, _p} -> k end, fn {_k, p} -> p end)
  end

end

defmodule HostCore.Actors.ActorSupervisor do
  use DynamicSupervisor
  alias HostCore.Actors.ActorModule
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Process.flag(:trap_exit, true)
    :ets.new(:call_aliases, [:named_table])
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
      {List.first(Registry.keys(Registry.ActorRegistry, pid)), pid}
    end)
    |> Enum.group_by(fn {k, _p} -> k end, fn {_k, p} -> p end)
  end

  def find_actor(public_key) do
    Map.get(all_actors(), public_key, [])
  end

  def terminate_actor(public_key, count) when count > 0 do
    precount = Supervisor.which_children(HostCore.Actors.ActorSupervisor) |> length

    children =
      Registry.lookup(Registry.ActorRegistry, public_key)
      |> Enum.take(count)
      |> Enum.map(fn {pid, _v} -> pid end)

    remaining = max(precount - count, 0)
    children |> Enum.each(fn pid -> ActorModule.halt(pid) end)

    HostCore.Actors.ActorModule.publish_actor_stopped(public_key, remaining)

    {:ok}
  end
end

# idea, actor watcher genserver that monitors a path for changes
# when a file is modified and closed, stop that actor and start the new one
# A new subscription can be created with a handle_info call, map from path to actor ID in state
defmodule WasmcloudHost.ActorWatcher do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: :actor_watcher)
  end

  def hotwatch_actor(pid, path, replicas) do
    GenServer.call(pid, {:hotwatch_actor, path, replicas}, 60_000)
  end

  def stop_hotwatch(pid, actor_id) do
    GenServer.call(pid, {:stop_hotwatch, actor_id})
  end

  # Determines if an actor is currently being hotwatched for changes
  def is_hotwatched?(pid, actor_id) do
    GenServer.call(pid, {:is_hotwatched, actor_id})
  end

  def init(_args) do
    {:ok, %{}}
  end

  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    if :modified in events and :closed in events do
      {:ok, bytes} = File.read(path)
      actor_id = Map.get(state, path, "")
      existing_actors = HostCore.Actors.ActorSupervisor.find_actor(actor_id)

      cond do
        # noop, no actor is registered under that path
        actor_id == "" ->
          {:noreply, state}

        # Actor was deleted, stop handling events for that actor
        existing_actors == [] ->
          {:noreply, Map.delete(state, path)}

        true ->
          replicas = existing_actors |> Enum.count()

          HostCore.Actors.ActorSupervisor.terminate_actor(
            actor_id,
            replicas
          )

          start_actor(bytes, replicas)
          {:noreply, state}
      end
    end

    {:noreply, state}
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_call({:hotwatch_actor, path, replicas}, _from, state) do
    with {:ok, bytes} <- File.read(path),
         :ok <- start_actor(bytes, replicas),
         {:ok, claims} <- HostCore.WasmCloud.Native.extract_claims(bytes) do
      if Map.get(state, path) != nil do
        # Already watching this actor, don't re-subscribe
        {:reply, :ok, state}
      else
        {:ok, watcher_pid} = FileSystem.start_link(dirs: [path])
        FileSystem.subscribe(watcher_pid)
        {:reply, :ok, Map.put(state, path, claims.public_key)}
      end
    else
      {:error, err} ->
        {:reply, {:error, "Unable to start actor, #{err}"}, state}

      _ ->
        {:reply, {:error, "Unable to start actor"}, state}
    end
  end

  def handle_call({:stop_hotwatch, actor_id}, _from, state) do
    new_state =
      case state |> Enum.find(fn {_k, v} -> v == actor_id end) do
        {path, _actor_id} -> Map.delete(state, path)
        nil -> state
      end

    {:reply, :ok, new_state}
  end

  def handle_call({:is_hotwatched, actor_id}, _from, state) do
    case state
         |> Enum.find(fn {_k, v} -> v == actor_id end) do
      nil -> {:reply, false, state}
      _actor -> {:reply, true, state}
    end
  end

  def start_actor(bytes, replicas) do
    case 1..replicas
         |> Enum.reduce_while("", fn _, _ ->
           case HostCore.Actors.ActorSupervisor.start_actor(bytes) do
             {:stop, err} ->
               {:halt, "Error: #{err}"}

             _any ->
               {:cont, ""}
           end
         end) do
      "" -> :ok
      msg -> {:error, msg}
    end
  end
end

defmodule WasmcloudHost.ActorWatcher do
  use GenServer

  @reload_delay 1_000

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
    # Modified is emitted on Mac, Windows, and Linux when a file is changed
    if :modified in events do
      {:ok, _bytes} = File.read(path)
      actor_map = Map.get(state, path, %{})
      actor_id = Map.get(actor_map, :actor_id, "")
      is_reloading = Map.get(actor_map, :is_reloading, false)
      existing_actors = HostCore.Actors.ActorSupervisor.find_actor(actor_id)

      cond do
        # noop, no actor is registered under that path
        actor_id == "" ->
          {:noreply, state}

        # Actor was deleted, stop handling events for that actor
        existing_actors == [] ->
          {:noreply, Map.delete(state, path)}

        # File modified events already received, don't request another reload
        is_reloading ->
          {:noreply, state}

        true ->
          # Sending after a delay enables ignoring rapid-fire filesystem events
          Process.send_after(self(), {:reload_actor, path}, @reload_delay)
          new_actor = Map.put(actor_map, :is_reloading, true)
          {:noreply, Map.put(state, path, new_actor)}
      end
    end

    {:noreply, state}
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  # Reloads all instances of an actor with updated bytes from the specified path
  def handle_info({:reload_actor, path}, state) do
    {:ok, bytes} = File.read(path)
    actor_id = state |> Map.get(path, %{}) |> Map.get(:actor_id, "")
    existing_actors = HostCore.Actors.ActorSupervisor.find_actor(actor_id)

    replicas = existing_actors |> Enum.count()

    HostCore.Actors.ActorSupervisor.terminate_actor(
      actor_id,
      replicas
    )
    start_actor(bytes, replicas)

    new_actor = %{actor_id: actor_id, is_reloading: false}
    {:noreply, Map.put(state, path, new_actor)}
  end

  def handle_call({:hotwatch_actor, path, replicas}, _from, state) do
    with {:ok, bytes} <- File.read(path),
         :ok <- start_actor(bytes, replicas),
         {:ok, claims} <- HostCore.WasmCloud.Native.extract_claims(bytes) do
      if Map.get(state, path, nil) != nil do
        # Already watching this actor, don't re-subscribe
        {:reply, :ok, state}
      else
        {:ok, watcher_pid} = FileSystem.start_link(dirs: [path])
        FileSystem.subscribe(watcher_pid)
        {:reply, :ok, Map.put(state, path, %{actor_id: claims.public_key, is_reloading: false})}
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
         |> Enum.find(fn {_k, v} -> Map.get(v, :actor_id, nil) == actor_id end) do
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

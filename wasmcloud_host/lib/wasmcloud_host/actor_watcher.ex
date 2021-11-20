# idea, actor watcher genserver that monitors a path for changes
# when a file is modified and closed, stop that actor and start the new one
# A new subscription can be created with a handle_info call, map from path to actor ID in state
defmodule WasmcloudHost.ActorWatcher do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: :actor_watcher)
  end

  def hotwatch_actor(pid, path) do
    GenServer.call(pid, {:hotwatch_actor, path})
  end

  def init(_args) do
    {:ok, %{}}
  end

  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    if :modified in events and :closed in events do
      {:ok, bytes} = File.read(path)
      actor_id = Map.get(state, path, "")

      cond do
        # noop, no actor is registered under that path
        actor_id == "" ->
          {:noreply, state}

        # Actor was deleted, stop handling events for that actor
        HostCore.Actors.ActorSupervisor.find_actor(actor_id) == [] ->
          #TODO: consider if I need to stop the file event watcher
          {:noreply, Map.delete(state, path)}

        true ->
          #TODO: Scale shouldn't be available
          HostCore.Actors.ActorSupervisor.terminate_actor(actor_id, 1)
          HostCore.Actors.ActorSupervisor.start_actor(bytes)
          {:noreply, state}
      end
    end

    {:noreply, state}
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_call({:hotwatch_actor, path}, _from, state) do
    with {:ok, bytes} <- File.read(path),
         {:ok, _pid} <- HostCore.Actors.ActorSupervisor.start_actor(bytes),
         {:ok, claims} <- HostCore.WasmCloud.Native.extract_claims(bytes),
         {:ok, watcher_pid} <- FileSystem.start_link(dirs: [path]),
         :ok <- FileSystem.subscribe(watcher_pid) do
      {:reply, :ok, Map.put(state, path, claims.public_key)}
    else
      {:error, err} ->
        {:reply, {:error, "Unable to start actor, #{err}"}, state}

      _ ->
        {:reply, {:error, "Unable to start actor"}, state}
    end
  end
end

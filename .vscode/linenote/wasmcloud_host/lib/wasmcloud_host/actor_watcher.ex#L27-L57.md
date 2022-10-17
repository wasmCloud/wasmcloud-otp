## Bug Report

As it is currently implemented, most of what is being done inside the `if` clause that changes the state will not be reflected in the GenServer itself.

### Reasoning

Every statement in elixir is an expression, which means that it has a value. This includes `if`, `case`, `cond` etc.

Another important thing to keep note of is the fact that the return value of a function is the last statement in that function.

### Bug

In this function, we have an `if` statement that only tests for the truthy part. However, the last statement in the function is `{:noreply, state}`

The assumption being made here is that because within the `if` statement there are returns such as `{:noreply, new_state}`, with some clauses event making changes to the state, then the new state will be picked up by the GenServer

This assumption is wrong based on the fact that the last statement for this function is `{:noreply, state}`.

As such, any changes made to the state in the `if` clause will not be reflected.

This bug is being caused by the lack of recognition that while the return value of the `if` may be `{:noreply, new_state}`, this is not the last statement in this function, hence, not updating the state to the new_state.

### Bug fix

In order to fix this bug, include an explicit `else` clause for the `if` statement.

```elixir
@impl GenServer
def handle_info({:file_event, _, {path, event}}, state) do
    if :modified in events do
        handle_modified(state, path)
    else
        {:noreply, state}
    end
end

defp handle_modified(state, path) do
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
          Process.send_after(self(), {:reload_actor, path}, @reload_delay_ms)
          new_actor = Map.put(actor_map, :is_reloading, true)
          {:noreply, Map.put(state, path, new_actor)}
    end
end

```

## Observations

1. While this is okay, it is a bit hard to follow what is happening because of the high cognitive load required to understand what is happening.

   - The main reason for this is because of the rebinding of the variable `actor_map` through a series of steps

## Opportunity for refactoring

In order to fix the above issue, this could be refactored to:

```elixir
def add_actor(pk, host, previous_map) do
    host= Map.get(previous_map, host, %{})

    host
    |> update_host_actors(pk)
    |> then(&Map.put(previous_map, host, &1))
end

defp update_host_actors(host, pk) do
    actors = Map.get(host, :actors, %{})

    actors
    |> update_actor_with_pk(pk)
    |> then(&Map.put(host, :actors, &1))
end

defp update_actor_with_pk(actors, pk) do
    actor = Map.get(actors, pk, %{})

    actor
    |> Map.put(:status, "Awaiting")
    |> Map.update(:count, 0, & &1 + 1)
    |> then(&Map.put(actors, pk, &1))
end

```

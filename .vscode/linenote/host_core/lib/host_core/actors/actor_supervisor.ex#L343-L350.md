## Opportunity for refactoring

In this function there's a call to `Enum.filter` followed by `Enum.map/2`

While this is not a problem, it does means that the resulting list is iterated twice (once with Enum.filter and the next with `Enum.map`)

In order to reduce this, `for` can be used to both filter and return the desired list. Read more [here](https://hexdocs.pm/elixir/Kernel.SpecialForms.html#for/1)

Also, this is a check that can be enforced using credo as will with credo checks (Again, excercise caution)

## Recommended refactor

```elixir
def terminate_actor(public_key, 0, annotations) do
    halt_required_actors(public_key, annotations)
    HostCore.Actors.ActorRpcSupervisor.stop_rpc_subscriber(public_key)

    :ok
end

defp halt_required_actors(public_key, annotations) do
    for {pid, _} <- get_actors(puplic_key),
        existing = get_annotations(pid),
        Map.merge(existing, annotations) == existing,
        do: ActoModule.halt(pid)
end

defp get_actors(public_key), do: Registry.lookup(Registry.ActorRegistry, public_key)


defp get_annotations(pid), do: HostCore.Actors.ActorModule.annotations(pid)

```

## Questions

1. Is the call to this really necessary?

   - In the previous line, there's a call to:

     ```elixir
     Enum.map(pids, fn {_, pid, _, _} ->
         {List.first(Registry.keys(ActorRegistry, pid)), pid}
     end)

     ```

     The call above would result to something similar to this:

     ```elixir
     [{k1, pid}, {k2, pid2}, {k3, pid3}, ...{kN, pidN}]

     # where ki, k2 upto kN will never be a list
     ```

Because of the explicit call to `List.first/1`, it means that there might not be a need to group the results at all.

# Recommendations

If this is the case, then this can be done without the need for chaining the calls to `Enum`

```elixir
specs = Supervisor.which_children(ActorSupervisor)

for {_, pid, _, _} <- specs do
    key =
        ActorRegistry
        |> Registry.keys(pid)
        |> List.first()

    %{key => [pid]}
end

```

## Opportunity for refactoring

- Besides the above comments, this function could be refactored to:

```elixir
ActorSupervisor
|> Supervisor.which_children()
|> Enum.map(&get_keys_for_pid/1)
|> Enum.group_by(fn {k, _} -> k end, fn {_, p} -> p end)


defp get_keys_for_pid(pid) do
    keys = Registry.keys(ActorRegistry, pid)

    {List.fist(keys), pid}
end
```

### Reasoning for the above refactor

Whenever you need to chain functions together, always ensure that the first thing in the chain is plain Elixir term and not a function call.

Doing so increases the readability of the code. This can be enforced using `credo` check, [Credo.Check.Refactor.PipeChainStart](https://hexdocs.pm/credo/Credo.Check.Refactor.PipeChainStart.html)

```elixir
# don't do

function_call()
|> some_call()
|> another_call()

# favour

value = function_call()

value
|> some_call()
|> another_call()

```

## Opportunity for refactor

In the selected functions, there's an opportunity to use pattern matching on the function clauses.

```elixir
def guest_response(_, %{memory: memory}, agent, ptr, len) do
    memory
    |> Wasmex.Memory.read_binary(ptr, len)
    |> then(&Agent.update(fn content -> %{content | guest_response: &1} end))
end

def guest_error(_, %{memory: memory}, agent, ptr, len) do
    memory
    |> Wasmex.Memory.read_binary(ptr, len)
    |> then(&Agent.update(fn content -> %{content | guest_error: &1} end))
end

```

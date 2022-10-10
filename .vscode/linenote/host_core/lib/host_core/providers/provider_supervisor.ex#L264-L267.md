## Possibility for refactoring

Prefer the use of `for` to `Enum` here:

```elixir
def terminate_all do
    for {_, pk, link, _, _} <- all_providers(), do: terminate_provider(pk, link)
end

```

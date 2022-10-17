## Opportunity for refactoring

This line could be replaced with `Map.update/4` instead:

```elixir
count = Map.update(actor_info, :count, 0, & &1 + 1)

```

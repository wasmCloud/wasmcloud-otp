## Opportunity for refactoring

- Use `Map.get/3` instead

```elixir
annotations = Map.get(start_actor_command, "annotations", %{})

```

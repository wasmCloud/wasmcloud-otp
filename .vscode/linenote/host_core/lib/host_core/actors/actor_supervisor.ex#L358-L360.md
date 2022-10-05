## Opportunity for refactor

This also does an Enum.map followed by and Enum.each and can be refactored into:

```elixir
for {k, v} <- all_actors(), count = Enum.count(v), do: terminate(k, count, %{})

```

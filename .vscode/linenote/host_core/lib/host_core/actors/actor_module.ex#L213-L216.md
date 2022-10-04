## Opportunity for refactoring

- Make use of pattern matching here

```elixir
%{claims: %{public_key: pk, name: name}, instance_id: i_id} = Agen.get(agent, &(&1))

```

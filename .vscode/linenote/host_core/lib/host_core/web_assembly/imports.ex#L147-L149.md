## Opportunity for refactor:

Use pattern matching here instead:

```elixir
%{claims: %{public_key: actor}} = Agent.get(agent, &(&1))

```

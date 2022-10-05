## Opportunity for refactoring

Whenever possible favour the use of pattern matching on function heads

```elixir
def validate_actor_for_udate({_, %{rev: rev}}, %{revisions: new_rev}) do
    {old_rev, _} = Integer.parse(rev)

    if new_rev > old_rev, do: :ok, else: :error
end

```

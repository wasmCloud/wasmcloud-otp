## Opportunity for refactoring

Anytime you find yourself chaining an `Enum.map/2` to an `Enum.filter/2` or vice-versa, always first consider using `for` not unless it's untenable.

This avoids the unintended consequence of iterating over the lists twice

### Possible refactors

```elixir
def ocis_for_key(public_key) when is_binary(public_key) do
    for {ociref, pk} <- :ets.tab2list(:refmap_table), pk == public_key, do: ociref
end

```

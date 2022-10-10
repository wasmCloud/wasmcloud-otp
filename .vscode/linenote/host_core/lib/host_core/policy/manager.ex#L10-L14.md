## Opportunity for refactoring

(Optional)

Because this is a map that is being pattern matched on the function body, we can ignore the other keys that we do not need, except when you're also pattern matching on the shape of the match

### Possible Refactoring

```elixir
@doc """
Remember to add documentation to this function
"""
@impl Gnat.Server
def request(%{body: body}) do
    # code here
end

```

However, if there's a need to also pattern match on the shape of the map been passed as an argument to the function, then it's important to remember to include a default clause, to avoid the raising of the `FunctionClauseErrror`

```elixir
@doc """
Documentation here
"""
@impl Gnat.Server
def request(%{body: body, reply_to: _, topic: _}) do
    # code here
end

def request(_) do
    # maybe return an error tuple from here (your choice)
end

```

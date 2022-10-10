## Opportunity for refactoring

1. Put this into the function match clause header.

   - However, if you're uncertain that the key will not exist, then the current implementation is okay.

## Possible refactoring

```elixir
def request(%{topic: topic, body: body, reply_to: to,  headers: headers} = red) do
    # rest of the function body
end

```

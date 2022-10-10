## Opportunity for refactoing

This function as currently implemented has a number of readability issues:

1. It's unclear what this function is doing because it is not documented at all.

   - Not unless you're the author, this function is hard to understant

2. The repeated use of `List.delete_at` does not give an indication of what exactly is being deleted.

   - Despite the single comments added above each line, the comments themselves do no offer clear explanation of what actually is being deleted

### Recommedations:

1. Ensure that functions are well documented, with clear details on what the function does

2. For this instance, do not shy away from creating new functions (even if they will have a single line of code) whose names describe what they are actually doing.

### Possible refactoring

```elixir
@doc """
Document what this function is doing cleary
"""
@impl Gnat.Server
def render(%{topic: topic, body: body}) do
    topic
    |> String.split(".")
    |> delete_lc()
    |> delete_prefix()
    |> List.to_tuple()
    |> handle_request(body)

    {:reply, ""}
end

# if possible rename this to a more approprate name
# and offer some small note on what the lc is and
# why we delete it
defp delete_lc(list), do: List.delete_at(list, 0)

# if possible rename this to a more approprate name
# and offer some small note on what the prefix is and
# why we delete it
defp delete_prefix(list), do: List.delete_at(list, 0)


```

A better solution would be to split the string into part (in this case 3, though countercheck to make sure it's accurate) and complete avoid the calls to `List.delete_at/2`

```elixir
@doc """
Documentation for function here
"""
@impl True
def render(%{topic: topic, body: body}) do
    # countercheck this part to ensure it's the correct
    # number of parts (feel free to change it to the
    # correct number)
    [_, _, part] = String.split(topic, ".", parts: 3)

    part
    |> String.split(".")
    |> List.to_tuple()
    |> handle_request(body)

    {:reply, ""}
end

```

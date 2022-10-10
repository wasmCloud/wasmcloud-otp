## Opportunity for refactoring

As it is currently implemented, this piece of code is is hard to understand, if you're not the author of the code.

This is due to two reasons:

1. The function `request/1` does not contain anu documentation letting the reader know what this function does.

2. The piping from line 23 to line 30, is very uninformatiive due to the repeated use of `List.delete_at/2`

### Recommendations

1. As a practice, especially considering that this is an open source project, ensure that there's a lot documentation throughout the code base.

   - As such, for this instance, add documentation telling the reader what this function does.

2. Instead of the repeated calls to `List.delete_at/2`, create more meaningfully named functions and chain to those instead.

   - Having completely new functions that have one line is not a problem, because it:

     a. Provides documentation to what is happening
     b. Ensures the function has single responsibilty
     c. Complies with the one level of abstraction required by the calling function

   - Read more on this in the books `Clean Code` and `Designing Elixir Systems with OTP`

### Possible refactor

```elixir
@doc """
Documentation on what this function is doing
"""
def request(%{topic: topic, body: body, reply_to: reply_to} = req) do
    req
    |> Map.get()
    |> reconstitute_trace_context()

    Logger.debug("Recieved control interface request on #{topic}")

    topic
    |> String.split(".")
    |> delete_wasmbus()
    |> delete_ctl_part()
    |> delete_prefix()
    |> List.to_tuple()
    |> handle_request(body, reply_to)
end

defp delete_wasmbus(list), do: List.delete_at(0)

defp delete_ctl_part(list), do: List.delete_at(0)

defp delete_prefix(list), do: List.delete_prefix(0)

```

An even better implementation would be to completely avoid the calls to `List.delete_at/2` and use pattern matching.

This implementation makes the assumption that you know how many parts the string will be split into (in this case, 4 parts would suffice)

**Note**

If you refactor to this, countercheck the parts to be certain that it is the required number, and use that instead.

```elixir
def request(%{topic: topic, body: body, reply_to: reply_to} = req) do
    req
    |> Map.get()
    |> reconstitute_trace_context()

    Logger.debug("Recieved control interface request on #{topic}")

    [_, _, _, part] = String.split(topic, ".", parts: 4)

    part
    |> String.split(".")
    |> List.to_tuple()
    |> handle_request(body, reply_to)
end


```

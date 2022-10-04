## Opportunity for refactoring

- When using `if` the `else` clause will only be invoked if the condition evalutates to either `false` or `nil`.

As such, there is no need to explicitly check if a value is equal to or not equal to `nil`

```elixir
defp host_response(_, context, agent, ptr) do
    if hr = Agent.get(agent, fn content -> content.host_response) do
        Wasmex.Memory.write_binary(context.memory, ptr, hr)
    end

    # since elixir returns the value of the last expression as the
    # return value of a function, then this function will always return
    # nil
    nil
end

```

**Note**

This refactor can be done across the functions that follow this:

1. host_error/4
2. host_response_len/3
3. host_error_len/3

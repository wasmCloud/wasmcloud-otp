## Opportunity for refactoring

There's no need to check whether or not a value is not equal to nil when using `if`:

```elixir
def console_log(_, context, ptr, len) do
    if text = Wasmex.Memory.read_string(context.memory, ptr, len) do
        Logger.info("Log from guest (non-actor): #{text}")
    end

    nil
end

```

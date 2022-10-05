## Opportunities for refactoring

```elixir
bytes
|> IO.iodata_to_binary()
|> start_actor(ref, count, annotations)

```

## Recommendation

1. Add `credo` to the project and add this check to the configuration to ensure that such code is always checked for and denied, [Credo.Check.Readability.NestedFunctionCalls](https://hexdocs.pm/credo/Credo.Check.Readability.NestedFunctionCalls.html)

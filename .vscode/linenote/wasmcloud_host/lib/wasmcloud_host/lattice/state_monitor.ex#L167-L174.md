## Opportunity for refactoring

(Optional)

As a matter of preference, this can be be refactored to:

```elixir
defp handle_event(state, body) do
    body
    |> Cloudevents.from_json!()
    |> then(&process_event(state, &1))
end

```

The only difference is that the function makes use of the `then/2` function.

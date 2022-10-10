## Opportunity for refactoring

```elixir
body
|> Jason.decode!()
|> handle_stream_create_response()

```

- Add credo check to prevent nesting of function calls like this.

## Possibilty for refactoring

```elixir
case msg["level"] do
    "error" -> Logger.error(text, actor_id: actor)
    "info" -> Logger.info(text, actor_id: actor)
    "warn" -> Logger.warn(text, actor_id: actor)
    _ -> Logger.debug(text, actor_id: actor)
end

```

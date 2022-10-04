## Refactoring opportunity

- Instead of using `Map.delete/2` by chaining it, this can also be accomplished by `Map.drop/2`

```elixir
keys = [
    :cluster_adhoc,
    :cache_deliver_inbox,
    :host_seed,
    :enable_structured_logging,
    :structured_log_level,
    :host_key
]

Map.drop(config, keys)
```

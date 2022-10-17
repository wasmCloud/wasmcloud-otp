## Notes

When defining a live component in Phoenix LiveView, do most of the preparation of the socket within the `update/2` callback and not within the `mount/1`

This is because of how the life cycle for live components works.

### First render

Whenever a live component is first rendered, it will go through the following life cycle

```
mount/1 -> update/2 -> render/1
```

However, during consequent rerenders, the life cycle will be:

```
update/2 -> render/1
```

Read more about this [here](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html#module-life-cycle)

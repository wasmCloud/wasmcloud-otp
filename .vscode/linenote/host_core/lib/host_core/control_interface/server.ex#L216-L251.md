## Opportunity for refactoring

There's a call to `Task.start/1`, which spawns a process that is not supervised.

While this is a fire an forget kind of a process, always ensure that processes spawned are always supervised.

This ensures that, even though what you want to do is a `fire and forget` request, it will always be restarted if something goes wrong and also be logged as well

## Recommendations:

1. Throughout the code base there's a call to `Task.start/1` or `Task.async/1` which are all not supervised.

   - Replace this calls with their supervised counter parts: `Task.Supervisor.start_child/1` and/or `Task.Supervisor.async/1`

   - Read the documentation [here](https://hexdocs.pm/elixir/1.13.4/Task.Supervisor.html) to know how to include this to your supervision tree.

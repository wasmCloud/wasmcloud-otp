## Opportunity for refactoring

While as it is, it works, this can can be imporved further by moving the logic for termination to the `terminate/2` callback

This is because the terminate callback also does the exact same thing as the what this `handle_info/2` callback is doing.

### Possible refactor

```elixir
@impl GenServer
def handle_info({:do_stop, _}, state) do
    # returning stop with the reason normal
    # will delegate this to the terminate/2 callback
    # and invoke the logic inside terminate

    # As a note, depending on how long you think the
    # process will take to terminate, you can increase
    # the shutdown value in `use GenServer, shutdown: 10_000` at the top of the module
    {:stop, :normal, state}
end

```

**Note**

Calling of `:init.stop/0` will shutdown the node and will do so gracefully allowing for the parent supervisor to shutdown all it's children.

Depending on the `:shutdown` value of each of the children, the supervisor will wait for each child to terminate based on it.

Should it take longer than the shutdown, the supervisor will brutally kill the child.

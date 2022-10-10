## Opportunity for reafactoring

As it is currently implemented using `Enum.map/2` and `Enum.reject/2`, the list is being itereated through twice.

In order to avoid this, use `for` which will only iterate through the list once.

The function `provider_for_pid/1` expects a `pid`, however, the way it's being called from the function `all_providers/0`, there's a possibility that a pid
will not be given to the function.

Instead, it will receive the atom `:restarting`, because the call to `DynamicSupervisor.which_children/1` also could return children that are in the process of restarting.

While this has not been accounted for in the code base, it has not raised any problem so far, because there's no check when calling `Registry.keys(ProviderRegistry, key)`, hence returning `nil`

This could be left as is, however, it should be noted that in the future should there be a requirement to ensure that the argument passed is strictly a `pid`, then this should be revisited.

Alternatively, this could be fixed now by checking that its a `pid` and fixing any failing tests that result from the refactor

### Possible refactor:

```elixir
def all_providers do
    for {_, pid, _, _} <- get_children(), provider = provider_for_pid(pid), !is_nil(provider) do
        provider
    end
end

def get_chidlren do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> not_restarting()
end

defp not_restarting(children) do
    # An important thing to note here is that there's the possibility
    # that at the time DynamicSupervisor.which_children/1 is called
    # some of its chidlren might be restarting, resulting in a response
    # like {_, :restarting, _, _}

    # What this function does is to return a list of only the chidlren
    # that are not running.

    # An important question to consider at this point is:
    # Since this function might be used to terminate all the children,
    # what do you do with the children that might be restarting?
    for {_, term, _, _} = child <- children, is_pid(term), do: child
end

```

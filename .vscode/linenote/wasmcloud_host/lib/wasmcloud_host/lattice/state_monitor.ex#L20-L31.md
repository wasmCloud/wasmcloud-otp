## Opportunity for refactoring

While as it is it is okay, this can be improved by declaring the defstruct using defaults

Doing so will allow the for the code to be much cleaner, easier to read and easier to maintain

Another improvement that could be made is to remove the nested `State` module and declare it outside the module

Remember, it is absolutely okay to have more than one module in a single file with a few caveats:

    1. Ensure the modules are closely related. A good example would what we have here

    2. Ensure that the module names are unique throughout the application

### Possible refactor

```elixir
# state_monitor.ex
defmodule Wasmcloud.Lattice.StateMonitor.State do
    # remember that when defining structs, keys with default
    # values should always come last
    defstruct [
        :hosts,
        claims: %{},
        refmaps: %{},
        linkdefs: %{},
    ]
end


defmodule Wasmcloud.Lattice.StateMonitor do
    @moduledoc """
    Add documentations for this module
    """
    use GenServer, restart: :transient

    alias HostCore.Host

    alias Phoenix.PubSub

    # alias the state in order to use it
    alias __MODULE__.State

    require Logger

    ## code before init ...

    @impl GenServer
    def init(_) do
        prefix = Host.lattice_prefix()
        topic = "wasmbus.evt.#{prefix}"

        {:ok, _sub} = Gnat.sub(:control_nats, self(), topic)
        Registry.register(Registry.EventMonitorRegistry, "cache_loader_events", [])

        {:ok, new_state(), {:continue, :retrieve_cache}}
    end

    defp new_state do
        host_key = Host.host_key()
        labels = Host.host_labels()
        hosts = %{
            host_key => %{
                actors: %{},
                provides: %{},
                labels: labels
            }
        }

        %State{hosts: hosts}
    end

end

```

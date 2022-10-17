## Opportunity for refactoring

As it is currently implemented, this code is a bit un readable.

In order to refactor this, make use of the CRC method (Constructor Reducer Convertor) method.

### Possible refactor

This could be refactord to:

```elixir
@impl true
def mount(_, _, socket) do
    # Keep in mind that mount gets called twice except when its
    # been mounted in a live session.
    # The first time in a disconnected state and the second time
    # in a connected state.

    # Always ensure that subscriptions such as below are done in the
    # connected state.
    if connected?(socket) do
        WasmcloudHostWeb.Endpoint.subscribe("lattice:state")
        WasmcloudHostWeb.Endpoint.subscribe("frontend")
    end

    {:ok, prepare_socket(socket)}
end


defp prepare_socket(socket) do
    socket
    |> assign_hosts()
    |> assign_linkdefs()
    |> assign_ocirefs()
    |> assign_claims()
    |> assign_selected_host()
    |> assign(:open_modal, nil)
end

defp assign_hosts(socket) do
    assign(socket, :hosts, StateMonitor.get_hosts())
end

def assign_linkdefs(socket) do
    assign(socket, :linkdefs, StateMonitor.get_linkdefs())
end

def assign_ocirefs(socket) do
    assign(socket, :ocirefs, StateMonitor.get_ocirefs())
end

defp assign_claims(socket) do
    assign(socket, :claims, StateMonitor.get_claims())
end

defp assign_selected_host(socket) do
    assign(socket, :selected_host, StateMonitor.host_key())
end


```

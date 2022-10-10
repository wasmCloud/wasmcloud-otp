## Possibility for refactoring

(Optional)

For this refactor, I make use of the `then/2` function to pipe the results into HostCore.Nats.safe_pub/4

```elixir
def public_actor_start_failed(%{"provider_ref" => ref, "link_name" => l_name}, msg) do
    prefix = HostCore.Host.lattice_prefix()

    payload = %{
        error: msg,
        link_name: l_name,
        provider_ref: ref
    }

    payload
    |> CloudEvent.new("prefix_start_failed")
    |> then(%HostCore.Nats.safe_pub(:control_nats, "wasmbus.evt.#{prefix}", &1))
end

```

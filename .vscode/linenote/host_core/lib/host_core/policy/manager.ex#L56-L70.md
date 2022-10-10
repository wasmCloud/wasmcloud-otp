## Opportunity for refactoring

- Consider creating an intermediate variable for this payload

- Doing so will increate the readability of the code

### Possible refactor

```elixir
payload = %{
    requestId: request_id,
    source: source,
    target: target,
    action: action,
    host: %{
        publicKey: HostCore.Host.host_key(),
        issuer: HostCore.Host.issuer(),
        latticeId: HostCore.Host.lattice_prefix(),
        labels: HostCore.Host.host_labels(),
        clusterIssuers: HostCore.Host.cluster_issuers()
    }
}

payload
|> evaluate(topic)
|> cache_decision(source, target, action, request_id)

```
